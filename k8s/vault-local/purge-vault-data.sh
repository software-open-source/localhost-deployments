#!/usr/bin/env bash
# =====================================================================
# purge-vault-data.sh — Dọn dẹp toàn bộ dữ liệu phát sinh của lab vault-local
#
#   ./purge-vault-data.sh              # hỏi xác nhận + BẮT BUỘC nhập password sudo
#   YES=true ./purge-vault-data.sh     # bỏ qua câu hỏi [y/N], nhưng VẪN bắt buộc sudo
#
# ⚠️  BẢO VỆ: nếu cluster vault-local ĐANG CHẠY → script TỪ CHỐI purge.
#     Phải chạy ./uninstall-vault-local.sh trước rồi mới được purge.
#
# Những thứ sẽ bị xóa:
#   - Thư mục: data/, tls/
#   - File:    .vault-local-cluster.generated.yaml
#              .vault-local-service.generated.yaml
#              vault-keys.txt
#
# Log: purge-vault-data.log (644 — người khác chỉ đọc, không xóa được)
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"

YES=${YES:-false}
CLUSTER_NAME=vault-local
LOG_FILE="purge-vault-data.log"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo -e "${BLUE}[$(ts)]${NC} $*";   echo "[$(ts)] $*"   >> "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[✔ $(ts)]${NC} $*"; echo "[✔ $(ts)] $*" >> "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[! $(ts)]${NC} $*"; echo "[! $(ts)] $*" >> "$LOG_FILE"; }
fail() { echo -e "${RED}[✗ $(ts)]${NC} $*" >&2; echo "[✗ $(ts)] $*" >> "$LOG_FILE"; exit 1; }

# Cluster "sống thật": có trong danh sách kind VÀ API server phản hồi
cluster_is_alive() {
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME" && \
  kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null 2>&1
}

# ---------------------------------------------------------------------
# Header log + banner
# ---------------------------------------------------------------------
{
  echo "================================================"
  echo " PURGE VAULT-LOCAL DATA — $(ts)"
  echo " User: $(whoami) (UID $(id -u)) | Dir: $(pwd)"
  echo "================================================"
} >> "$LOG_FILE"

echo "=================================================="
echo " Script sẽ xóa (nếu có): data/, tls/,"
echo " .vault-local-cluster.generated.yaml,"
echo " .vault-local-service.generated.yaml, vault-keys.txt"
echo " 🛡️  Cluster đang chạy → TỪ CHỐI purge."
echo " 🔐 Bắt buộc nhập password sudo để xóa."
echo "=================================================="

# ---------------------------------------------------------------------
# CHẶN: cluster đang chạy thì KHÔNG cho xóa (kiểm tra ĐẦU TIÊN)
# ---------------------------------------------------------------------
if cluster_is_alive; then
  warn "Cluster $CLUSTER_NAME ĐANG CHẠY — từ chối purge!"
  warn "Lý do: Vault đang chạy có thể ghi lại data/ ngay sau khi xóa,"
  warn "và các file do container tạo (khác UID) cũng không dọn sạch được."
  fail "Hãy chạy ./uninstall-vault-local.sh trước, rồi quay lại purge."
fi
log "Cluster không chạy — cho phép purge."

# ---------------------------------------------------------------------
# Xác nhận [y/N] — YES=true bỏ qua bước này, nhưng sudo KHÔNG BAO GIỜ bỏ
# ---------------------------------------------------------------------
if [[ "$YES" != true ]]; then
  read -r -p "Xác nhận xóa? [y/N] " ans
  [[ "$ans" =~ ^[yY] ]] || { log "Người dùng hủy — không xóa gì cả."; exit 0; }
fi

# ---------------------------------------------------------------------
# BẮT BUỘC xác thực sudo: phải nhập password trước khi đụng vào bất cứ thứ gì
# ---------------------------------------------------------------------
command -v sudo >/dev/null 2>&1 || fail "Máy không có lệnh sudo — không thể purge."
log "Yêu cầu xác thực sudo — nhập password của user '$(whoami)'..."
if ! sudo -v; then
  fail "Xác thực sudo thất bại hoặc bị hủy — purge bị hủy, không xóa gì cả."
fi
ok "Đã xác thực sudo thành công"

log "Bắt đầu dọn dẹp..."

# ---------------------------------------------------------------------
# Xóa thư mục: rm thường → sudo rm (credential sudo đã cache sẵn)
# ---------------------------------------------------------------------
purge_dir() {
  local target="$1"
  if [[ ! -d "$target" ]]; then
    log "Bỏ qua thư mục không tồn tại: $target/"
    return
  fi

  if rm -rf "$target" 2>/dev/null; then
    ok "Đã xóa thư mục: $target/"
    return
  fi

  warn "rm thường thất bại với $target/ (file do container tạo, khác UID) → dùng sudo..."
  if sudo rm -rf "$target" 2>/dev/null; then
    ok "Đã xóa thư mục: $target/ (bằng sudo)"
    return
  fi

  warn "Không xóa được $target/ — anh kiểm tra lại giúp em."
}

purge_file() {
  local target="$1"
  if [[ -f "$target" ]]; then
    if rm -f "$target" 2>/dev/null || sudo rm -f "$target" 2>/dev/null; then
      ok "Đã xóa file: $target"
    else
      warn "Không xóa được file: $target"
    fi
  else
    log "Bỏ qua file không tồn tại: $target"
  fi
}

# ---------------------------------------------------------------------
# Thực hiện
# ---------------------------------------------------------------------
purge_dir  "data"
purge_dir  "tls"
purge_file ".vault-local-cluster.generated.yaml"
purge_file ".vault-local-service.generated.yaml"
purge_file "vault-keys.txt"

chmod 644 "$LOG_FILE"
ok "Đã dọn dẹp xong. Log: $(pwd)/$LOG_FILE (644 rw-r--r--)"