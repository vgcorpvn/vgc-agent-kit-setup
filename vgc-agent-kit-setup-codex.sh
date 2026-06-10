#!/usr/bin/env bash
set -euo pipefail

# Không redirect global stdout/stdin — dùng /dev/tty trực tiếp per-command
# để tránh conflict khi chạy qua curl | bash
TTY=/dev/tty

_echo() { echo "$@" >"$TTY"; }
_echon() { echo -n "$@" >"$TTY"; }

VGC_DIR="$HOME/.vgc-agent-kit"
SKILLS_DIR="$HOME/.agents/skills"

_echo "======================================"
_echo "  VGC Agent Kit — Setup (Codex CLI)"
_echo "======================================"
_echo ""

# Step 1: Check git
if ! command -v git &>/dev/null; then
    _echo "[vgc-agent-kit] Git chưa được cài đặt."
    if [[ "$(uname)" == "Darwin" ]]; then
        _echo "[vgc-agent-kit] Đang cài Git qua Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        _echo ""
        _echo "Vui lòng hoàn tất cài đặt Xcode Command Line Tools trong popup,"
        _echo "sau đó chạy lại script này."
        exit 1
    else
        _echo "[vgc-agent-kit] Vui lòng cài Git:"
        _echo "  Ubuntu/Debian: sudo apt install git"
        _echo "  Fedora:        sudo dnf install git"
        exit 1
    fi
fi

_echo "[vgc-agent-kit] Git OK: $(git --version)"

# Step 2: Check existing installation
if [ -d "$VGC_DIR" ]; then
    _echo "[vgc-agent-kit] Đã cài đặt trước đó tại $VGC_DIR"
    _echon "Ghi đè? (y/N): "
    read -r overwrite <"$TTY"
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        _echo "[vgc-agent-kit] Huỷ bỏ."
        exit 0
    fi
    rm -rf "$VGC_DIR"
fi

# Step 3: Ask for token
_echo ""
_echo "Cần GitHub Personal Access Token (PAT) với quyền repo:read."
_echo "Tạo tại: https://github.com/settings/tokens"
_echo ""

# Dùng /dev/tty trực tiếp cho cả input lẫn prompt — tránh bị pipe nuốt mất
_echon "Nhập GitHub token: "
# stty -echo: ẩn ký tự khi gõ (giống read -s)
stty -echo <"$TTY"
read -r GITHUB_TOKEN <"$TTY"
stty echo <"$TTY"
_echo ""  # xuống dòng sau khi nhập xong

if [ -z "$GITHUB_TOKEN" ]; then
    _echo "[vgc-agent-kit] ERROR: Token không được để trống."
    exit 1
fi

# Step 4: Clone repo
REPO_URL="https://${GITHUB_TOKEN}@github.com/vgcorpvn/vgc-agent-kit.git"
_echo "[vgc-agent-kit] Đang clone repository..."
git clone --quiet "$REPO_URL" "$VGC_DIR" 2>"$TTY" || {
    _echo "[vgc-agent-kit] ERROR: Clone thất bại. Kiểm tra lại token và quyền truy cập repo."
    exit 1
}

_echo "[vgc-agent-kit] Clone thành công."

# Step 5: Store credentials for future pulls
git -C "$VGC_DIR" config credential.helper store
echo "https://${GITHUB_TOKEN}@github.com" \
    | git -C "$VGC_DIR" credential approve 2>/dev/null || true

# Step 6: Symlink skills
mkdir -p "$SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$SKILLS_DIR/$skill_name"
    _echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# Step 7: Install cronjob
CRON_CMD="$VGC_DIR/scripts/vgc-agent-kit-update-codex.sh"
CRON_ENTRY="0 9 * * * $CRON_CMD >/dev/null 2>&1"

(crontab -l 2>/dev/null | grep -v "vgc-agent-kit-update-codex"; echo "$CRON_ENTRY") | crontab -
_echo "[vgc-agent-kit] Cronjob cài đặt: chạy mỗi ngày lúc 9h sáng."

# Step 8: Add alias
SHELL_RC="$HOME/.zshrc"
if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

ALIAS_LINE="alias vgc-agent-kit-update-codex=\"$VGC_DIR/scripts/vgc-agent-kit-update-codex.sh\""

if ! grep -q "vgc-agent-kit-update-codex" "$SHELL_RC" 2>/dev/null; then
    echo "" >>"$SHELL_RC"
    echo "# VGC Agent Kit" >>"$SHELL_RC"
    echo "$ALIAS_LINE" >>"$SHELL_RC"
    _echo "[vgc-agent-kit] Alias added to $SHELL_RC"
fi

_echo ""
_echo "======================================"
_echo "  Setup hoàn tất!"
_echo "======================================"
_echo ""
_echo "  Skills location: $SKILLS_DIR"
_echo "  Repo location:   $VGC_DIR"
_echo "  Auto-update:     Daily lúc 9h sáng"
_echo "  Manual update:   vgc-agent-kit-update-codex"
_echo ""
_echo "  Mở terminal mới hoặc chạy: source $SHELL_RC"
_echo ""