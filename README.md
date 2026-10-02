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