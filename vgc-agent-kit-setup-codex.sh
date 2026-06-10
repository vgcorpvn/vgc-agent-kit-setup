#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script thất bại tại dòng $LINENO (exit code $?)" >&2' ERR

VGC_DIR="$HOME/.vgc-agent-kit"
SKILLS_DIR="$HOME/.agents/skills"

echo "======================================"
echo "  VGC Agent Kit — Setup (Codex CLI)"
echo "======================================"
echo ""

# Step 1: Check git
if ! command -v git &>/dev/null; then
    echo "[vgc-agent-kit] Git chưa được cài đặt."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "[vgc-agent-kit] Đang cài Git qua Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        echo ""
        echo "Vui lòng hoàn tất cài đặt Xcode Command Line Tools trong popup,"
        echo "sau đó chạy lại script này."
        exit 1
    else
        echo "[vgc-agent-kit] Vui lòng cài Git:"
        echo "  Ubuntu/Debian: sudo apt install git"
        echo "  Fedora:        sudo dnf install git"
        exit 1
    fi
fi

echo "[vgc-agent-kit] Git OK: $(git --version)"

# Step 2: Check existing installation — reuse if already cloned (e.g. by Claude setup)
SKIP_CLONE=false
if [ -d "$VGC_DIR" ]; then
    if [ -d "$VGC_DIR/.git" ]; then
        echo "[vgc-agent-kit] Repo đã tồn tại tại $VGC_DIR — dùng lại (skip clone)."
        git -C "$VGC_DIR" pull --ff-only 2>/dev/null || true
        SKIP_CLONE=true
    else
        echo "[vgc-agent-kit] Thư mục $VGC_DIR tồn tại nhưng không phải git repo."
        read -rp "Ghi đè? (y/N): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo "[vgc-agent-kit] Huỷ bỏ."
            exit 0
        fi
        rm -rf "$VGC_DIR"
    fi
fi

if [ "$SKIP_CLONE" = false ]; then
    # Step 3: Ask for token
    echo ""
    echo "Cần GitHub Personal Access Token (PAT) với quyền repo:read."
    echo "Tạo tại: https://github.com/settings/tokens"
    echo ""
    read -rsp "Nhập GitHub token: " GITHUB_TOKEN
    echo ""

    if [ -z "$GITHUB_TOKEN" ]; then
        echo "[vgc-agent-kit] ERROR: Token không được để trống."
        exit 1
    fi

    # Step 4: Clone repo
    REPO_URL="https://${GITHUB_TOKEN}@github.com/vgcorpvn/vgc-agent-kit.git"
    echo "[vgc-agent-kit] Đang clone repository..."
    git clone --quiet "$REPO_URL" "$VGC_DIR" || {
        echo "[vgc-agent-kit] ERROR: Clone thất bại. Kiểm tra lại token và quyền truy cập repo."
        exit 1
    }

    echo "[vgc-agent-kit] Clone thành công."

    # Step 5: Store credentials for future pulls
    git -C "$VGC_DIR" config credential.helper store
    echo "https://${GITHUB_TOKEN}@github.com" \
        | git -C "$VGC_DIR" credential approve 2>/dev/null || true
fi

# Step 6: Symlink skills
mkdir -p "$SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$SKILLS_DIR/$skill_name"
    echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# Step 7: Install cronjob (best-effort — không kill script nếu fail)
if EXISTING_CRON="$(crontab -l 2>/dev/null || true)" && \
   FILTERED_CRON="$(echo "$EXISTING_CRON" | grep -v "vgc-agent-kit-update-codex" || true)" && \
   CRON_CMD="$VGC_DIR/scripts/vgc-agent-kit-update-codex.sh" && \
   CRON_ENTRY="0 9 * * * $CRON_CMD >/dev/null 2>&1" && \
   (echo "$FILTERED_CRON"; echo "$CRON_ENTRY") | crontab -; then
    echo "[vgc-agent-kit] Cronjob cài đặt: chạy mỗi ngày lúc 9h sáng."
else
    echo "[vgc-agent-kit] WARNING: Không thể cài cronjob. Bạn có thể cập nhật thủ công: vgc-agent-kit-update-codex"
fi

# Step 8: Add alias
SHELL_RC="$HOME/.zshrc"
if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

ALIAS_LINE="alias vgc-agent-kit-update-codex=\"$VGC_DIR/scripts/vgc-agent-kit-update-codex.sh\""

if ! grep -q "vgc-agent-kit-update-codex" "$SHELL_RC" 2>/dev/null; then
    {
        echo ""
        echo "# VGC Agent Kit"
        echo "$ALIAS_LINE"
    } >> "$SHELL_RC" || echo "[vgc-agent-kit] WARNING: Không thể ghi alias vào $SHELL_RC"
    echo "[vgc-agent-kit] Alias added to $SHELL_RC"
fi

# Load alias ngay trong session hiện tại
eval "$ALIAS_LINE" 2>/dev/null || true

echo ""
echo "======================================"
echo "  Setup hoàn tất!"
echo "======================================"
echo ""
echo "  Skills location: $SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Auto-update:     Daily lúc 9h sáng"
echo "  Manual update:   vgc-agent-kit-update-codex"
echo ""