# Hướng dẫn cài đặt

⚠️ **QUAN TRỌNG:** Bạn bắt buộc phải khởi tạo cơ sở dữ liệu và bảng trước khi khởi chạy Docker để tránh lỗi Filer.

### Bước 1: Tạo cơ sở dữ liệu

Truy cập vào PostgreSQL và chạy lệnh sau:

```sql
CREATE DATABASE seaweedfs_db;

```

### Bước 2: Tạo bảng `filemeta`

Kết nối vào cơ sở dữ liệu `seaweedfs_db` vừa tạo và thực thi lệnh sau:

```sql
CREATE TABLE IF NOT EXISTS filemeta (
    dirhash BIGINT NOT NULL,
    name VARCHAR(65535) COLLATE "C" NOT NULL,
    directory VARCHAR(65535) COLLATE "C" NOT NULL,
    meta bytea,
    PRIMARY KEY (dirhash, name)
);

CREATE INDEX IF NOT EXISTS idx_filemeta_directory ON filemeta (directory);

```

### Bước 3: Khởi chạy hệ thống

Chỉ chạy lệnh dưới đây sau khi đã hoàn tất thành công Bước 1 và Bước 2:

```bash
docker compose up -d

```