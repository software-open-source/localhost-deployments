#!/usr/bin/env bash
# =====================================================================
# uninstall.sh — Gỡ bỏ lab vault-local
#
#   ./uninstall.sh                 # xóa cluster, GIỮ lại cert/keys/data
#   CLEAN=true ./uninstall.sh      # xóa cluster + vault-keys.txt + tls/ + data/*
#   YES=true  ...                  # kèm theo để không hỏi xác nhận (chạy script/CI)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

CLEAN=${CLEAN:-false}
YES=${YES:-false}

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo "=================================================="
echo " Uninstall lab vault-local  (cluster: vault-local)"
echo " Chế độ CLEAN: $CLEAN"
echo "=================================================="

# ---- Xác nhận trước khi phá ----
if [[ "$YES" != true ]]; then
  if [[ "$CLEAN" == true ]]; then
    read -r -p "Xóa cluster + TOÀN BỘ file local (keys, tls/, data/*)? [y/N] " ans
  else
    read -r -p "Xóa cluster vault-local (giữ lại keys/tls/data)? [y/N] " ans
  fi
  [[ "$ans" =~ ^[yY] ]] || { echo "Đã hủy, không xóa gì cả."; exit 0; }
fi

# ---------------------------------------------------------------------
# 1. Xóa kind cluster
# ---------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx vault-local; then
  kind delete cluster --name vault-local
  log "Đã xóa cluster vault-local"
else
  warn "Cluster vault-local không tồn tại — bỏ qua"
fi

# Best-effort dọn context kubeconfig còn sót (nếu có)
kubectl config delete-context kind-vault-local >/dev/null 2>&1 || true
kubectl config delete-cluster kind-vault-local >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 2. Dọn file local (chỉ khi CLEAN=true)
# ---------------------------------------------------------------------
if [[ "$CLEAN" == true ]]; then
  rm -f  vault-keys.txt test-tls-secret.yaml
  rm -rf tls
  if [[ -d data ]]; then
    find data -mindepth 1 -delete     # xóa NỘI DUNG, giữ lại thư mục data/
  fi
  log "Đã dọn vault-keys.txt, tls/, test-tls-secret.yaml, data/*"
else
  warn "Giữ lại cert/keys/data — muốn sạch tinh: CLEAN=true ./uninstall.sh"
fi

log "👋 Uninstall hoàn tất. Cài lại bất cứ lúc nào: ./install-test.sh"