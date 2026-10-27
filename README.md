# docker
 Docker quickstart

## Dọn dẹp sâu Docker trên toàn hệ thống

1. **Dừng toàn bộ container:** Lệnh bash.
Lệnh này ép dừng tất cả các container đang chạy để giải phóng các volume và network đang bị khóa.

```bash
docker stop $(docker ps -aq)

```

*Xác minh:* Chạy `docker ps` sẽ không hiển thị bất kỳ container nào đang hoạt động.


2. **Xóa toàn bộ container:** Lệnh bash.
Gỡ bỏ hoàn toàn các container khỏi hệ thống để cắt đứt liên kết với các volume.

```bash
docker rm $(docker ps -aq)

```

*Xác minh:* Chạy `docker ps -a` sẽ không trả về kết quả nào.


3. **Dọn dẹp triệt để tài nguyên:** Lệnh bash.
Xóa sạch toàn bộ image, volume, network và build cache rác.

```bash
docker builder prune -f
docker image prune -a -f
docker system prune -a --volumes -f
docker volume rm $(docker volume ls -q)
docker compose up --no-build
```

*Xác minh:* Lệnh sẽ in ra tổng dung lượng ổ đĩa vừa được giải phóng. Anh có thể kiểm tra lại tab Volumes trong VS Code hoặc chạy `docker volume ls` để xác nhận danh sách đã trống.

---

## Nginx gateway thuần (legacy)

Gateway Nginx tự sinh route vẫn còn trong repo nhưng đã được thay bằng Nginx Proxy Manager bên dưới. Nếu cần khởi chạy lại cấu hình cũ, chạy `dockers/nginx/nginx/setup.sh`; script này dùng cổng 80/443 nên cần dừng Nginx Proxy Manager trước.

Script Nginx cũ tự nối các container đang chạy vào Docker network và tạo route theo tên container. Container chạy với `network_mode: host` không thể tham gia Docker bridge network. Chứng chỉ tự ký có thể khiến trình duyệt cảnh báo.

Có thể cấu hình domain và network trước khi chạy:

```bash
GATEWAY_DOMAIN=localhost GATEWAY_NETWORK=nginx_gateway dockers/nginx/nginx/setup.sh
```

Để chỉ định cổng HTTP, thêm Docker label `gateway.http.port=<cổng>` hoặc truyền `GATEWAY_HTTP_PORTS='tên-container=cổng'`. Có thể đặt `gateway.http.scheme=https` cho upstream HTTPS hoặc `gateway.enable=false` để tắt route HTTP.

## Nginx Proxy Manager

Để chuyển gateway sang giao diện quản lý Nginx Proxy Manager và tự đồng bộ container, chạy:

```bash
./dockers/nginx/nginx-proxy-manager/setup.sh
```

Compose dùng image `jlesage/nginx-proxy-manager`, với cổng host 80/443 chuyển tiếp tới cổng container 8080/4443 và giao diện quản trị tại `http://localhost:8100` (container port 8181). Dữ liệu NPM lưu trong `dockers/nginx/nginx-proxy-manager/config`. Khi chuyển từ image `jc21`, cấu hình cũ ở `data/` được giữ nguyên nhưng image mới dùng thư mục `config/` riêng; không xóa `data/`.

Script dừng gateway Nginx cũ để giải phóng cổng 80/443, nối các container đang chạy vào `nginx_gateway`, kéo image và khởi động Nginx Proxy Manager. Lần đầu, đăng nhập tại `http://localhost:8100` (mặc định `admin@example.com` / `changeme` nếu chưa đổi), hoàn tất thiết lập tài khoản và cập nhật thông tin đăng nhập vào `dockers/nginx/nginx-proxy-manager/.env`. Chạy lại setup để bật watcher tự đồng bộ. Mật khẩu chỉ lưu trong file `.env` đã bị Git ignore; file dùng raw env format nên không bọc giá trị bằng dấu nháy. Yêu cầu Docker Compose v2.30 trở lên.

Watcher kiểm tra container mỗi 30 giây, tự nối container vào network, tạo/cập nhật Proxy Host dạng `http://<tên-container>.localhost`, đồng thời xóa các Proxy Host do chính watcher quản lý khi service không còn chạy. Các Proxy Host tạo thủ công trong NPM không bị sửa/xóa. HTTP chỉ được định tuyến cho cổng nhận diện là HTTP; database/TCP không được đưa vào HTTP gateway. Có thể điều chỉnh `SYNC_INTERVAL`, `GATEWAY_DOMAIN`, hoặc chỉ định cổng bằng Docker label `gateway.http.port`, `gateway.http.scheme` và tắt route bằng `gateway.enable=false` trong file Compose của service. Riêng container đã chạy sẵn có thể dùng `GATEWAY_HTTP_PORTS='tên-container=cổng'` trong `.env`.

Mặc định Proxy Host dùng HTTP phía client. Để bật HTTPS cho các host tự đồng bộ, import wildcard certificate vào NPM một lần rồi đặt ID chứng chỉ vào `NPM_CERTIFICATE_ID` trong `.env`; chứng chỉ self-signed vẫn khiến trình duyệt cảnh báo. Let's Encrypt cần domain công khai, DNS trỏ đúng máy chủ và cổng 80/443 truy cập được từ Internet.

### Cấu hình thủ công Proxy Host với HTTPS local

Ví dụ cấu hình Swagger của `backend-service` tại `https://backend-service.localhost/swagger-ui/index.html`:

1. Mở NPM tại `http://localhost:8100`, vào **Hosts → Proxy Hosts → Add Proxy Host**.
2. Trong tab **Details**, điền **Domain Names** là `backend-service.localhost` rồi nhấn Enter để xác nhận thành domain tag. Đặt **Scheme** là `http`, **Forward Hostname / IP** là `backend-service`, **Forward Port** là `8086`; bật **Websockets Support** rồi chuyển sang tab **SSL**.
3. Tạo chứng chỉ wildcard dùng chung cho các domain `.localhost`. Vào **Certificates → Add SSL Certificate → Custom**:
   - **Name:** `localhost-wildcard`
   - **Certificate Key:** `dockers/nginx/nginx/tls/privkey.pem`
   - **Certificate:** `dockers/nginx/nginx/tls/fullchain.pem`
   - **Intermediate Certificate:** để trống.
4. Quay lại Proxy Host `backend-service.localhost`, mở tab **SSL**, chọn `localhost-wildcard` thay vì **Request a new Certificate**. Có thể bật **Force SSL**, rồi bấm **Save**.
5. Mở `https://backend-service.localhost/swagger-ui/index.html`. Chứng chỉ hiện tại là self-signed nên trình duyệt sẽ cảnh báo chưa tin cậy; đây là điều bình thường nếu chưa cài CA/chứng chỉ tin cậy trên máy khách.

Không dùng **Request a new Certificate** cho domain `.localhost`: Let's Encrypt không cấp chứng chỉ cho domain local. Nếu danh sách **SSL Certificate** chưa có `localhost-wildcard`, hãy tạo và lưu custom certificate trước rồi mới chọn nó trên Proxy Host.

Watcher cần mount `/var/run/docker.sock` để đọc container và gắn network. Quyền Docker socket tương đương quyền quản trị Docker trên máy; socket chỉ được cấp cho watcher, không cấp cho NPM. Không dùng tính năng này trên máy có workload không tin cậy. Container chạy với `network_mode: host` không thể tham gia Docker network dùng chung.