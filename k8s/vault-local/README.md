# VAULT-LOCAL — Deploy HashiCorp Vault trên localhost (kind)

Bài lab triển khai **Vault server mode (HTTPS)** trên cluster kind ngay tại máy cá nhân, thực hành chuỗi khái niệm:
kind cluster → Namespace → PV/PVC (hostPath + extraMounts) → ConfigMap/Secret → TLS (openssl) → Deployment (resources, env) → Service NodePort → port-mapping ra host → init/unseal.

## Sơ đồ đường đi

```
https://localhost:8443  (trên host — cổng mặc định, đổi được trong .env)
        │   kind extraPortMappings (HOST_PORT → NODE_PORT)
        ▼
node control-plane :30443   (mở bởi Service NodePort)
        │   kube-proxy chuyển tiếp
        ▼
Pod vault :8200 (HTTPS)   (chạy trên node worker)
        │   mount PVC pvc1 tại /vault/data
        ▼
/data trong worker   ⇄   <thư mục project>/data trên host
```

## Cấu trúc thư mục

| File / thư mục | Vai trò |
|---|---|
| `.env` | Tuỳ chỉnh cổng `HOST_PORT` / `NODE_PORT` (tuỳ chọn — mặc định 8443/30443) |
| `vault-local-cluster.yaml` | **Template** kind cluster: giá trị mặc định hợp lệ + comment đánh dấu; KHÔNG apply bằng kubectl |
| `vault-local-service.yaml` | **Template** Service NodePort: `nodePort` mặc định 30443 |
| `.vault-local-cluster.generated.yaml` / `.vault-local-service.generated.yaml` | Config đã render cho máy hiện tại (tự sinh ra, không commit) |
| `vault-local-namespace.yaml` | Namespace `vault-local` |
| `vault-local-pv.yaml` / `vault-local-pvc.yaml` | PV `pv1` (hostPath `/data` trong worker, nodeAffinity worker) / PVC `pvc1` |
| `vault-local-configmap.yaml` | ConfigMap `app-config` (APP_ENV, LOG_LEVEL, `vault-config.hcl` server mode + TLS) |
| `vault-local-secret.yaml` | Secret `app-secret` (username/password — base64) |
| `vault-local-tls-secret.yaml` | Secret `vault-tls` (tls.crt / tls.key / ca.crt) |
| `vault-local-development.yaml` | Deployment `vault`: resources CPU/RAM, env từng key từ ConfigMap/Secret, mount PVC + config + TLS |
| `install-vault-local.sh` / `uninstall-vault-local.sh` | Script cài đặt / gỡ bỏ tự động |
| `vault-keys.txt` | 5 unseal keys + root token (tự sinh ra — **tuyệt đối không commit**) |
| `data/` | Storage Vault trên host (bền vững qua restart) |
| `tls/` | CA + certificate sinh bằng openssl |

## 0. Điều kiện tiên quyết

- Podman/Docker đang chạy (kind chạy node bằng container).
- Đã cài `kind`, `kubectl`, `openssl`, `curl`.
- `vault-local-cluster.yaml` là file của **kind** → tạo cluster bằng `kind create cluster` (qua bản generated); các `*.yaml` còn lại là manifest Kubernetes → `kubectl apply -f`.
- Hai file template (`cluster`, `service`) luôn là YAML **hợp lệ** với giá trị mặc định → VS Code không báo lỗi, và có thể dùng trực tiếp nếu không cần đổi cổng/đường dẫn.

---

## 1. Cài đặt thủ công (chạy từng lệnh)

### 1.0. Tuỳ chỉnh cổng bằng `.env` (tuỳ chọn)

```bash
# Cổng truy cập Vault UI trên máy host (đụng cổng thì đổi số khác)
HOST_PORT=8443

# NodePort trong cluster — BẮT BUỘC nằm trong khoảng 30000-32767
NODE_PORT=30443
```

### 1.1. Thứ tự chạy các file

| # | File | Lệnh | Vai trò |
|---|------|------|---------|
| 1 | `vault-local-cluster.yaml` | `mkdir -p data`<br>`source .env 2>/dev/null; HOST_PORT=${HOST_PORT:-8443}; NODE_PORT=${NODE_PORT:-30443}`<br>`sed -E -e "s#(hostPath: *)[^ ]+#\1$(pwd)/data#" -e "s#(hostPort: *)[0-9]+#\1$HOST_PORT#" -e "s#(containerPort: *)[0-9]+#\1$NODE_PORT#" vault-local-cluster.yaml > .vault-local-cluster.generated.yaml`<br>`kind create cluster --config .vault-local-cluster.generated.yaml` | Render đường dẫn + cổng của máy hiện tại rồi tạo cluster `vault-local` 2 node; map cổng host → node; mount `data/` của host vào `/data` trong worker. **Không kubectl apply, không chạy kind trực tiếp trên template.** |
| 2 | `vault-local-namespace.yaml` | `kubectl apply -f vault-local-namespace.yaml` | Tạo namespace `vault-local`. |
| — | *(tuỳ chọn)* | `kubectl config set-context --current --namespace=vault-local` | Đặt namespace mặc định, khỏi gõ `-n` mỗi lần. |
| 3 | `vault-local-pv.yaml` | `kubectl apply -f vault-local-pv.yaml` | PersistentVolume `pv1`: 5Gi, class `test-storage`, hostPath `/data` (trong worker), nodeAffinity ghè vào worker. |
| 4 | `vault-local-pvc.yaml` | `kubectl apply -f vault-local-pvc.yaml -n vault-local` | PersistentVolumeClaim `pvc1`: 150Mi → bind vào `pv1`. |
| 5 | `vault-local-configmap.yaml` | `kubectl apply -f vault-local-configmap.yaml -n vault-local` | ConfigMap `app-config` kèm `vault-config.hcl`. |
| 6 | `vault-local-secret.yaml` | `kubectl apply -f vault-local-secret.yaml -n vault-local` | Secret `app-secret` (username, password — base64). |
| 7 | *(openssl)* | xem khối lệnh bên dưới | Sinh CA + server certificate vào thư mục `tls/`. |
| 8 | `vault-local-tls-secret.yaml` | `kubectl create secret generic vault-tls -n vault-local --from-file=tls.crt=tls/tls.crt --from-file=tls.key=tls/tls.key --from-file=ca.crt=tls/ca.crt --dry-run=client -o yaml > vault-local-tls-secret.yaml`<br>`kubectl apply -f vault-local-tls-secret.yaml` | Đưa cert vào cluster thành Secret `vault-tls`. |
| 9 | `vault-local-development.yaml` | `kubectl apply -f vault-local-development.yaml` | Deployment `vault`: server mode, requests/limits CPU-RAM, env từng key, mount `pvc1` + config + TLS. |
| 10 | `vault-local-service.yaml` | `sed -E -e "s#(nodePort: *)[0-9]+#\1$NODE_PORT#" vault-local-service.yaml > .vault-local-service.generated.yaml`<br>`kubectl apply -f .vault-local-service.generated.yaml` | Service NodePort: 8200 → nodePort (mặc định 30443), hoàn thiện đường ra host. |

Khối lệnh sinh cert TLS (bước 7):

```bash
mkdir -p tls && cd tls
openssl req -x509 -newkey rsa:4096 -nodes -keyout ca.key -out ca.crt \
  -days 3650 -subj "/O=vault-local/CN=Vault Local CA"
openssl req -newkey rsa:2048 -nodes -keyout tls.key -out tls.csr \
  -subj "/O=vault-local/CN=localhost"
cat > san.cnf <<'EOF'
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = vault-service
DNS.3 = vault-service.vault-local.svc.cluster.local
IP.1 = 127.0.0.1
EOF
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out tls.crt -days 825 -sha256 -extfile san.cnf
cd ..
```

Apply dồn (nếu thích nhanh):

```bash
kubectl apply -f vault-local-namespace.yaml -f vault-local-pv.yaml
kubectl apply -n vault-local -f vault-local-pvc.yaml -f vault-local-configmap.yaml -f vault-local-secret.yaml
kubectl apply -f vault-local-development.yaml -f .vault-local-service.generated.yaml
```

### 1.2. Init + Unseal Vault (bắt buộc với server mode)

```bash
# Khởi tạo — LƯU output vào vault-keys.txt (5 unseal keys + 1 root token)
kubectl exec -n vault-local deploy/vault -- vault operator init | tee vault-keys.txt
chmod 600 vault-keys.txt

# Unseal bằng 3 trong 5 keys (lấy trong vault-keys.txt)
kubectl exec -n vault-local -it deploy/vault -- vault operator unseal <KEY_1>
kubectl exec -n vault-local -it deploy/vault -- vault operator unseal <KEY_2>
kubectl exec -n vault-local -it deploy/vault -- vault operator unseal <KEY_3>
```

### 1.3. Kiểm tra kết quả

```bash
kubectl get nodes -o wide
kubectl get pv,pvc,cm,secret,svc -n vault-local
kubectl get pods -n vault-local -o wide      # Pod phải nằm trên vault-local-worker
curl --cacert tls/ca.crt https://localhost:8443/v1/sys/health   # 8443 = HOST_PORT mặc định
```

- Vault UI: `https://localhost:8443/ui/` (hoặc cổng anh đặt trong `.env`) — token đăng nhập: **Initial Root Token** trong `vault-keys.txt`.
- Thử đồng bộ dữ liệu host ⇄ node: `touch data/hello.txt` rồi `podman exec vault-local-worker ls /data`.

---

## 2. Cài đặt tự động bằng `install-vault-local.sh`

```bash
# Cấp quyền thực thi (chỉ lần đầu)
chmod +x install-vault-local.sh

# Chạy
./install-vault-local.sh

# Muốn phá cluster làm lại từ đầu / áp dụng cổng mới trong .env:
FORCE=true ./install-vault-local.sh
```

Script tự động toàn bộ: nạp `.env` (validate `NODE_PORT` trong khoảng 30000–32767) → render template theo cổng + đường dẫn máy hiện tại → tạo cluster (tự dọn cluster "zombie") → apply manifest đúng thứ tự → chờ PVC Bound → sinh cert TLS (**lỗi openssl giờ in ra rõ ràng, không im lặng**) → tạo Secret → rollout Deployment → tự init + lưu `vault-keys.txt` (chmod 600) + tự unseal → kiểm tra HTTPS → in ra UI + root token. Script **idempotent**: chạy đi chạy lại không hỏng; sang máy khác không phải sửa bất cứ thứ gì.

**Lưu ý:** đổi cổng trong `.env` sau khi đã tạo cluster → bắt buộc `FORCE=true` (kind `extraPortMappings` đóng băng lúc tạo cluster); script tự cảnh báo nếu anh quên.

### Gỡ cài đặt

```bash
chmod +x uninstall-vault-local.sh     # cấp quyền (chỉ lần đầu)

./uninstall-vault-local.sh            # xóa cluster, GIỮ keys/tls/data
CLEAN=true ./uninstall-vault-local.sh # xóa cluster + keys + tls + data/* (factory reset)
```

---

## 3. Vì sao lại thứ tự đó?

- **Cluster trước**, nếu không `kubectl` báo `connection refused`.
- **`data/` phải tồn tại trước khi tạo cluster**, vì kind `extraMounts` bắt buộc thư mục host có sẵn.
- **PV trước PVC** để PVC bind ngay (ngược lại PVC sẽ `Pending` chờ).
- **ConfigMap/Secret trước Deployment** để Pod không treo `ContainerCreating` / `CreateContainerConfigError`.
- **Service sau cùng** (thật ra trước/sau Deployment đều được, Service chọn Pod theo label).
- **Init/unseal sau cùng**: Vault server mode chỉ nhận token sau khi đã unseal.

## 4. Các lỗi đã gặp trong lab & cách xử lý

| Hiện tượng | Nguyên nhân | Khắc phục |
|---|---|---|
| `dial tcp ... connection refused` khi chạy kubectl | Cluster chưa tạo / "zombie" sau khi reboot máy | Script tự dọn + tạo lại; hoặc tay: `kind delete cluster --name vault-local` rồi chạy lại |
| `statfs .../data: no such file or directory` khi tạo cluster | Thư mục `data/` chưa tồn tại | `mkdir -p data` trước khi `kind create cluster` (script tự làm) |
| Script dừng im lặng ngay sau "Sinh CA + server certificate..." | `set -e` + openssl bị giấu lỗi bởi `2>/dev/null`, thường do file hỏng sót trong `tls/` | `rm -rf tls/` rồi chạy lại; bản script mới bỏ giấu stderr và có `\|\| err "..."` từng bước |
| VS Code gạch đỏ `nodePort: __NODE_PORT__` | Schema Kubernetes bắt buộc `nodePort` là integer | Template dùng số mặc định + comment đánh dấu; script render bằng `sed -E` thay đúng con số |
| Port 8443 bị trùng với ứng dụng khác | 8443 là port "quốc dân" | Đổi `HOST_PORT`/`NODE_PORT` trong `.env` rồi `FORCE=true ./install-vault-local.sh` |
| `persistentvolumeclaim "pvc1" not found`, Pod `Pending` | PVC/ConfigMap/Secret rơi nhầm namespace | Luôn thêm `-n vault-local` khi apply các resource namespaced |
| `here-document ... wanted 'EOF'` | Dòng kết thúc `EOF` bị thụt lề / file lưu CRLF | `EOF` ở cột 0, line-ending LF (script dùng khối `echo` nên miễn nhiễm) |
| `NET::ERR_CERT_AUTHORITY_INVALID` | Cert tự ký (self-signed) | *Advanced → Proceed*; hoặc tin cậy CA: `sudo cp tls/ca.crt /usr/local/share/ca-certificates/vault-local-ca.crt && sudo update-ca-certificates` |
| `invalid token` ở màn hình Vault | Nhầm password của Secret (`password123`) với token Vault | Token đúng = **Initial Root Token** trong `vault-keys.txt` |
| Vault đã init nhưng mất `vault-keys.txt` | Mất chìa khóa trong khi `data/` còn storage cũ | Xóa `data/*` + xóa Pod để init lại (script tự xử lý) |
| `ls /data` trong node khác owner/giờ so với host | UID mapping của podman rootless + múi giờ UTC | Bình thường — vẫn là một thư mục |

## 5. Dọn dẹp & lưu ý

- `data/` trên host **không mất** khi xóa cluster (đó là mục đích của persistent storage).
- Muốn đổi `extraMounts` / `extraPortMappings` phải xóa cluster tạo lại (kind không sửa được cluster đang chạy).
- Cert **không phụ thuộc port** (SAN chỉ gồm hostname/IP) → đổi port không cần sinh lại cert.
- `.gitignore` nên có:
  ```
  .vault-local-cluster.generated.yaml
  .vault-local-service.generated.yaml
  vault-keys.txt
  tls/
  data/*
  ```
- File `.env` chỉ chứa số port, không chứa mật khẩu → commit hay ignore đều được (muốn chuẩn chỉnh: commit `.env.example`, ignore `.env`).