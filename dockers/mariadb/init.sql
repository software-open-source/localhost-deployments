-- ===============================================
-- MARIADB AUTO SETUP - Chỉ cần docker-compose up!
-- ===============================================

-- Tạo user root với quyền truy cập từ mọi host
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Tạo user 'user' với đầy đủ quyền admin
CREATE USER IF NOT EXISTS 'user'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'%' WITH GRANT OPTION;

-- Tạo các database mặc định
CREATE DATABASE IF NOT EXISTS initdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Tạo thêm user developer với quyền hạn chế hơn (nếu cần)
CREATE USER IF NOT EXISTS 'developer'@'%' IDENTIFIED BY 'dev123';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX ON *.* TO 'developer'@'%';

-- Xóa user anonymous (bảo mật)
DELETE FROM mysql.user WHERE User='';

-- Xóa test database (bảo mật)
DROP DATABASE IF EXISTS test;

-- Áp dụng tất cả thay đổi
FLUSH PRIVILEGES;

-- Thông báo hoàn thành
SELECT 'MariaDB Setup Complete!' as Status;