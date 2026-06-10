#!/usr/bin/env bash
set -euo pipefail

VGC_DIR="$HOME/.vgc-agent-kit"
CLAUDE_DIR="$HOME/.claude"
PLUGINS_FILE="$CLAUDE_DIR/plugins/installed_plugins.json"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
PLUGIN_KEY="vgc-agent-kit@local"

echo "======================================"
echo "  VGC Agent Kit — Setup (Claude Code)"
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

# Step 2: Check Claude Code installed
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "[vgc-agent-kit] ERROR: Thư mục $CLAUDE_DIR không tồn tại."
    echo "[vgc-agent-kit] Vui lòng cài Claude Code trước: https://claude.ai/download"
    exit 1
fi

echo "[vgc-agent-kit] Claude Code OK."

# Step 3: Check existing installation — reuse if already cloned (e.g. by Codex setup)
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
    # Step 4: Ask for token
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

    # Step 5: Clone repo
    REPO_URL="https://${GITHUB_TOKEN}@github.com/vgcorpvn/vgc-agent-kit.git"
    echo "[vgc-agent-kit] Đang clone repository..."
    git clone --quiet "$REPO_URL" "$VGC_DIR" || {
        echo "[vgc-agent-kit] ERROR: Clone thất bại. Kiểm tra lại token và quyền truy cập repo."
        exit 1
    }

    echo "[vgc-agent-kit] Clone thành công."

    # Step 6: Store credentials for future pulls
    git -C "$VGC_DIR" config credential.helper store
    echo "https://${GITHUB_TOKEN}@github.com" \
        | git -C "$VGC_DIR" credential approve 2>/dev/null || true
fi

# Step 7: Register as Claude Code plugin
mkdir -p "$CLAUDE_DIR/plugins"

# 7a: Update installed_plugins.json
if [ ! -f "$PLUGINS_FILE" ]; then
    echo '{"version":2,"plugins":{}}' > "$PLUGINS_FILE"
fi

INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

python3 -c "
import json, sys

plugins_path = '$PLUGINS_FILE'
plugin_key = '$PLUGIN_KEY'
install_path = '$VGC_DIR'
install_date = '$INSTALL_DATE'

with open(plugins_path, 'r') as f:
    data = json.load(f)

data.setdefault('version', 2)
data.setdefault('plugins', {})

data['plugins'][plugin_key] = [{
    'scope': 'user',
    'installPath': install_path,
    'version': '1.0.0',
    'installedAt': install_date,
    'lastUpdated': install_date
}]

with open(plugins_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" || {
    echo "[vgc-agent-kit] WARNING: Không thể đăng ký plugin tự động."
    echo "[vgc-agent-kit] Chạy Claude Code với: claude --plugin-dir $VGC_DIR"
}

echo "[vgc-agent-kit] Plugin đăng ký vào installed_plugins.json."

# 7b: Enable plugin in settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

python3 -c "
import json

settings_path = '$SETTINGS_FILE'
plugin_key = '$PLUGIN_KEY'

with open(settings_path, 'r') as f:
    data = json.load(f)

data.setdefault('enabledPlugins', {})
data['enabledPlugins'][plugin_key] = True

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" || {
    echo "[vgc-agent-kit] WARNING: Không thể bật plugin trong settings."
    echo "[vgc-agent-kit] Bật thủ công trong Claude Code: /plugins"
}

echo "[vgc-agent-kit] Plugin đã bật trong settings.json."

# Step 8: Install cronjob
UPDATE_SCRIPT="$VGC_DIR/scripts/vgc-agent-kit-update-claude.sh"
if [ -f "$UPDATE_SCRIPT" ]; then
    CRON_CMD="$UPDATE_SCRIPT"
else
    CRON_CMD="cd $VGC_DIR && git pull --ff-only"
fi
CRON_ENTRY="0 9 * * * $CRON_CMD >/dev/null 2>&1"

(crontab -l 2>/dev/null | grep -v "vgc-agent-kit-update"; echo "$CRON_ENTRY") | crontab -
echo "[vgc-agent-kit] Cronjob cài đặt: chạy mỗi ngày lúc 9h sáng."

# Step 9: Add alias
SHELL_RC="$HOME/.zshrc"
if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

ALIAS_LINE="alias vgc-agent-kit-update-claude=\"cd $VGC_DIR && git pull --ff-only\""

if ! grep -q "vgc-agent-kit-update-claude" "$SHELL_RC" 2>/dev/null; then
    echo "" >>"$SHELL_RC"
    echo "# VGC Agent Kit (Claude Code)" >>"$SHELL_RC"
    echo "$ALIAS_LINE" >>"$SHELL_RC"
    echo "[vgc-agent-kit] Alias added to $SHELL_RC"
fi

# Load alias in current session
eval "$ALIAS_LINE"

echo ""
echo "======================================"
echo "  Setup hoàn tất!"
echo "======================================"
echo ""
echo "  Plugin:        $PLUGIN_KEY"
echo "  Repo location: $VGC_DIR"
echo "  Auto-update:   Daily lúc 9h sáng"
echo "  Manual update: vgc-agent-kit-update-claude"
echo ""
echo "  Khởi động lại Claude Code để load skills."
echo "  Gõ / để xem danh sách skills."
echo ""
