#!/usr/bin/env bash
# =====================================================================
# install-vault-local.sh — Tự động cài đặt toàn bộ lab vault-local (Vault trên kind)
#
#   ./install-vault-local.sh                # cài bình thường
#   FORCE=true ./install-vault-local.sh     # xóa cluster cũ, cài lại từ đầu
#
# TUỲ BIẾN CỔNG BẰNG FILE .env (tuỳ chọn, không có thì dùng mặc định):
#   HOST_PORT=9443     # cổng Vault UI trên máy host (mặc định: 8443)
#   NODE_PORT=30443    # NodePort trong cluster       (mặc định: 30443)
#
# LƯU Ý: đổi port sau khi đã tạo cluster → phải chạy FORCE=true
# (kind extraPortMappings không thể sửa trên cluster đang chạy).
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

FORCE=${FORCE:-false}
NS=vault-local
CLUSTER_NAME=vault-local

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------
# 0. Nạp .env + mặc định + validate + điều kiện tiên quyết
# ---------------------------------------------------------------------
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
  log "Đã nạp file .env"
else
  warn "Không có .env → dùng cổng mặc định (HOST_PORT=8443, NODE_PORT=30443)"
fi
HOST_PORT=${HOST_PORT:-8443}
NODE_PORT=${NODE_PORT:-30443}

[[ "$HOST_PORT" =~ ^[0-9]+$ ]] || err "HOST_PORT phải là số (hiện tại: $HOST_PORT)"
[[ "$NODE_PORT" =~ ^[0-9]+$ ]] || err "NODE_PORT phải là số (hiện tại: $NODE_PORT)"
[[ "$NODE_PORT" -ge 30000 && "$NODE_PORT" -le 32767 ]] || err "NODE_PORT phải trong khoảng 30000-32767"

for cmd in kind kubectl openssl curl; do
  command -v "$cmd" >/dev/null 2>&1 || err "Thiếu lệnh: $cmd"
done
log "Điều kiện tiên quyết OK (kind, kubectl, openssl, curl)"

# ---------------------------------------------------------------------
# 0.5. Render template theo .env + đường dẫn máy hiện tại
# ---------------------------------------------------------------------
HOST_DATA_DIR="$(pwd)/data"
mkdir -p "$HOST_DATA_DIR"
chmod 777 "$HOST_DATA_DIR"
GENERATED_CLUSTER=".vault-local-cluster.generated.yaml"
GENERATED_SERVICE=".vault-local-service.generated.yaml"

# Cảnh báo nếu đổi HOST_PORT trong khi cluster cũ vẫn còn (port mapping đóng băng lúc tạo cluster)
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME" \
   && [[ -f "$GENERATED_CLUSTER" ]] \
   && ! grep -qE "hostPort: ${HOST_PORT}([^0-9]|$)" "$GENERATED_CLUSTER"; then
  warn "⚠️  HOST_PORT trong .env khác cluster hiện tại → cần FORCE=true để tái tạo cluster"
fi

# Render cluster config: thay hostPath / hostPort / containerPort theo .env + máy hiện tại
sed -E \
  -e "s|(hostPath: *)[^ ]+|\1${HOST_DATA_DIR}|" \
  -e "s|(hostPort: *)[0-9]+|\1${HOST_PORT}|" \
  -e "s|(containerPort: *)[0-9]+|\1${NODE_PORT}|" \
  vault-local-cluster.yaml > "$GENERATED_CLUSTER"

# Render service: thay nodePort theo .env
sed -E -e "s|(nodePort: *)[0-9]+|\1${NODE_PORT}|" \
  vault-local-service.yaml > "$GENERATED_SERVICE"

log "Đã render config → hostPort=$HOST_PORT, nodePort=$NODE_PORT, hostPath=$HOST_DATA_DIR"

# ---------------------------------------------------------------------
# 1. Tạo kind cluster (kiểm tra "sống thật", tự dọn cluster zombie)
# ---------------------------------------------------------------------
cluster_is_alive() {
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME" && \
  kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null 2>&1
}

if cluster_is_alive; then
  if [[ "$FORCE" == true ]]; then
    warn "FORCE=true → xóa cluster $CLUSTER_NAME cũ..."
    kind delete cluster --name "$CLUSTER_NAME"
    kind create cluster --config "$GENERATED_CLUSTER"
  else
    warn "Cluster $CLUSTER_NAME đang sống — bỏ qua bước tạo"
  fi
else
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    warn "Cluster $CLUSTER_NAME 'xác còn hồn mất' → dọn và tạo lại"
    kind delete cluster --name "$CLUSTER_NAME"
  fi
  log "Đang tạo kind cluster..."
  kind create cluster --config "$GENERATED_CLUSTER"
fi
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null
log "Nodes Ready"

# ---------------------------------------------------------------------
# 2. Namespace + PV/PVC + ConfigMap + Secret
# ---------------------------------------------------------------------
kubectl apply -f vault-local-namespace.yaml
kubectl apply -f vault-local-pv.yaml
kubectl apply -f vault-local-pvc.yaml -n $NS
kubectl apply -f vault-local-configmap.yaml -n $NS
kubectl apply -f vault-local-secret.yaml -n $NS
log "Đã apply namespace, PV/PVC, ConfigMap, Secret"

log "Chờ PVC pvc1 Bind trong namespace $NS..."
PVC_BOUND=false
for i in $(seq 1 30); do
  PHASE=$(kubectl get pvc pvc1 -n $NS -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
  if [[ "$PHASE" == "Bound" ]]; then
    PVC_BOUND=true
    break
  fi
  sleep 2
done
if [[ "$PVC_BOUND" == true ]]; then
  log "PVC pvc1 đã Bound thành công"
else
  err "Timeout hoặc PVC nằm sai namespace! Chạy 'kubectl get pvc --all-namespaces' để kiểm tra."
fi

# ---------------------------------------------------------------------
# 3. Cert TLS (openssl) + Secret vault-tls
# ---------------------------------------------------------------------
mkdir -p tls
if [[ -f tls/tls.crt && -f tls/tls.key && -f tls/ca.crt ]]; then
  # Kiểm tra thêm: file phải có nội dung (không phải 0 byte)
  if [[ -s tls/tls.crt && -s tls/tls.key && -s tls/ca.crt ]]; then
    warn "Cert TLS đã tồn tại — bỏ qua bước sinh"
  else
    warn "Cert TLS có file trống/rỗng → xóa và sinh lại"
    rm -f tls/tls.crt tls/tls.key tls/ca.crt tls/ca.key tls/tls.csr tls/ca.srl tls/san.cnf
  fi
fi

if [[ ! -f tls/tls.crt ]]; then
  log "Sinh CA + server certificate..."
  # Bỏ 2>/dev/null để lỗi in ra màn hình
  openssl req -x509 -newkey rsa:4096 -nodes -keyout tls/ca.key -out tls/ca.crt \
    -days 3650 -subj "/O=vault-local/CN=Vault Local CA" >/dev/null || err "Lỗi sinh CA"
  openssl req -newkey rsa:2048 -nodes -keyout tls/tls.key -out tls/tls.csr \
    -subj "/O=vault-local/CN=localhost" >/dev/null || err "Lỗi sinh CSR"
  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=CA:FALSE"
    echo "keyUsage = digitalSignature, keyEncipherment"
    echo "extendedKeyUsage = serverAuth"
    echo "subjectAltName = @alt_names"
    echo "[alt_names]"
    echo "DNS.1 = localhost"
    echo "DNS.2 = vault-service"
    echo "DNS.3 = vault-service.$NS.svc.cluster.local"
    echo "IP.1 = 127.0.0.1"
  } > tls/san.cnf
  openssl x509 -req -in tls/tls.csr -CA tls/ca.crt -CAkey tls/ca.key -CAcreateserial \
    -out tls/tls.crt -days 825 -sha256 -extfile tls/san.cnf >/dev/null || err "Lỗi ký cert"
fi

kubectl create secret generic vault-tls -n $NS \
  --from-file=tls.crt=tls/tls.crt \
  --from-file=tls.key=tls/tls.key \
  --from-file=ca.crt=tls/ca.crt \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
log "Secret vault-tls OK"

# ---------------------------------------------------------------------
# 4. Deployment + Service (service dùng bản đã render nodePort)
# ---------------------------------------------------------------------
kubectl apply -f vault-local-development.yaml
kubectl apply -f "$GENERATED_SERVICE"
kubectl rollout status deploy/vault -n $NS --timeout=180s >/dev/null
log "Deployment vault Running + Service NodePort OK"

# ---------------------------------------------------------------------
# 5. Init Vault nếu chưa + lưu keys vào vault-keys.txt
# ---------------------------------------------------------------------
STATUS_JSON=$(kubectl exec -n $NS deploy/vault -- vault status -format=json 2>/dev/null || true)
if echo "$STATUS_JSON" | grep -q '"initialized":false'; then
  log "Vault chưa init → chạy operator init..."
  kubectl exec -n $NS deploy/vault -- vault operator init | tee vault-keys.txt
  chmod 600 vault-keys.txt
else
  warn "Vault đã init."
  if [[ ! -f vault-keys.txt ]]; then
    warn "⚠️  Vault đã init nhưng MẤT vault-keys.txt → xóa data/ và init lại..."
    rm -rf data/*
    kubectl delete pod -n $NS -l app=vault
    kubectl rollout status deploy/vault -n $NS --timeout=120s >/dev/null
    kubectl exec -n $NS deploy/vault -- vault operator init | tee vault-keys.txt
    chmod 600 vault-keys.txt
  else
    log "Dùng lại vault-keys.txt hiện có"
  fi
fi

mapfile -t UNSEAL_KEYS < <(grep -E '^Unseal Key [0-9]+:' vault-keys.txt | awk '{print $4}')
ROOT_TOKEN=$(grep -E '^Initial Root Token:' vault-keys.txt | awk '{print $4}')
[[ ${#UNSEAL_KEYS[@]} -ge 3 ]] || err "Không đọc đủ unseal keys từ vault-keys.txt"

# ---------------------------------------------------------------------
# 6. Unseal nếu đang sealed (3/5 keys)
# ---------------------------------------------------------------------
if ! kubectl exec -n $NS deploy/vault -- vault status >/dev/null 2>&1; then
  log "Vault đang sealed → unseal bằng 3 keys..."
  for KEY in "${UNSEAL_KEYS[@]:0:3}"; do
    kubectl exec -n $NS deploy/vault -- vault operator unseal "$KEY" >/dev/null
  done
else
  log "Vault đã unsealed sẵn"
fi

# ---------------------------------------------------------------------
# 7. Kiểm tra HTTPS + tổng kết
# ---------------------------------------------------------------------
for i in $(seq 1 15); do
  curl -s --cacert tls/ca.crt "https://localhost:${HOST_PORT}/v1/sys/health" >/dev/null 2>&1 && break
  sleep 2
done

echo
log "🎉 CÀI ĐẶT HOÀN TẤT!"
echo "   Vault UI   : https://localhost:${HOST_PORT}/ui/"
echo "   Root token : $ROOT_TOKEN"
echo "   File keys  : $(pwd)/vault-keys.txt  (cất kỹ nhé anh!)"
echo "   Health     : curl --cacert tls/ca.crt https://localhost:${HOST_PORT}/v1/sys/health"