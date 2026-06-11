#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script thất bại tại dòng $LINENO (exit code $?)" >&2' ERR

VGC_ROOT="$HOME/.vgc"
VGC_DIR="$VGC_ROOT/agent-kit"
SKILLS_DIR="$HOME/.agents/skills"
WORKSPACE_DIR="$VGC_ROOT/agent-workspace"
CONFIG_DIR="$VGC_ROOT/config"
MOBILE_TOKEN_FILE="$CONFIG_DIR/mobile-token"

export GIT_TERMINAL_PROMPT=0

# ──────────────────────────────────────────
# Migration: move old paths into ~/.vgc/
# ──────────────────────────────────────────
mkdir -p "$VGC_ROOT"

if [ -d "$HOME/.vgc-agent-kit" ] && [ ! -d "$VGC_DIR" ]; then
    mv "$HOME/.vgc-agent-kit" "$VGC_DIR"
    echo "[vgc-agent-kit] Migrated ~/.vgc-agent-kit → ~/.vgc/agent-kit"
fi

if [ -d "$HOME/.vgc-agent-workspace" ] && [ ! -d "$WORKSPACE_DIR" ]; then
    mv "$HOME/.vgc-agent-workspace" "$WORKSPACE_DIR"
    echo "[vgc-agent-kit] Migrated ~/.vgc-agent-workspace → ~/.vgc/agent-workspace"
fi

if [ -d "$HOME/.config/vgc-agent-kit" ] && [ ! -d "$CONFIG_DIR" ]; then
    mv "$HOME/.config/vgc-agent-kit" "$CONFIG_DIR"
    echo "[vgc-agent-kit] Migrated ~/.config/vgc-agent-kit → ~/.vgc/config"
fi

echo "======================================"
echo "  VGC Agent Kit — Setup (Codex CLI)"
echo "======================================"
echo ""

# ──────────────────────────────────────────
# Step 1: Check git
# ──────────────────────────────────────────
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

# ──────────────────────────────────────────
# Step 2: Check/install gh CLI
# ──────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] GitHub CLI (gh) chưa cài. Đang cài..."
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            brew install gh 2>/dev/null || {
                echo "[vgc-agent-kit] WARNING: Không thể cài gh qua brew."
                echo "[vgc-agent-kit] Cài thủ công: https://cli.github.com/"
            }
        else
            echo "[vgc-agent-kit] WARNING: Homebrew chưa cài. Cài gh thủ công:"
            echo "  https://cli.github.com/"
        fi
    else
        if command -v apt-get &>/dev/null; then
            (type -p wget >/dev/null || sudo apt-get install wget -y) && \
            sudo mkdir -p -m 755 /etc/apt/keyrings && \
            wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
            sudo apt-get update && sudo apt-get install gh -y
        else
            echo "[vgc-agent-kit] WARNING: Không thể tự cài gh. Cài thủ công:"
            echo "  https://cli.github.com/"
        fi
    fi
fi

if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] gh CLI OK: $(gh --version | head -1)"
else
    echo "[vgc-agent-kit] WARNING: gh CLI không có. Một số skill sẽ không hoạt động."
fi

# ──────────────────────────────────────────
# Step 3: Token A — kit + workspace (read+write)
# ──────────────────────────────────────────
NEED_TOKEN_A=true

if command -v gh &>/dev/null; then
    if gh auth status -h github.com &>/dev/null; then
        echo ""
        echo "[vgc-agent-kit] gh CLI đã authenticated."

        REPOS_OK=true
        if ! gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
            REPOS_OK=false
        fi
        if ! gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
            REPOS_OK=false
        fi

        if [ "$REPOS_OK" = true ]; then
            echo "[vgc-agent-kit] Token A truy cập OK — dùng lại."
            NEED_TOKEN_A=false
        else
            echo "[vgc-agent-kit] Token A thiếu quyền — cần nhập token mới."
        fi
    fi
fi

if [ "$NEED_TOKEN_A" = true ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  Token A — cho kit + workspace (read+write)             │"
    echo "│                                                         │"
    echo "│  Quyền tối thiểu: repo, read:org                       │"
    echo "│  Token cần truy cập được:                               │"
    echo "│    • vgcorpvn/vgc-agent-kit        (read+write)         │"
    echo "│    • vgcorpvn/vgc-agent-workspace   (read+write)        │"
    echo "│                                                         │"
    echo "│  Tạo tại: https://github.com/settings/tokens            │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Nhập Token A: " TOKEN_A
    echo ""

    if [ -z "$TOKEN_A" ]; then
        echo "[vgc-agent-kit] ERROR: Token không được để trống."
        exit 1
    fi

    if command -v gh &>/dev/null; then
        echo "[vgc-agent-kit] Đang xác thực gh CLI với Token A..."
        if echo "$TOKEN_A" | gh auth login -h github.com --with-token 2>/dev/null; then
            echo "[vgc-agent-kit] gh auth OK."
        else
            echo "[vgc-agent-kit] ERROR: gh auth login thất bại."
            exit 1
        fi
    fi
fi

# ──────────────────────────────────────────
# Step 4: Setup gh as git credential helper
# ──────────────────────────────────────────
if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] Đồng bộ credentials: gh → git..."
    gh auth setup-git -h github.com 2>/dev/null || true
    echo "[vgc-agent-kit] git credential helper = gh CLI."
fi

# ──────────────────────────────────────────
# Step 5: Verify Token A repo access
# ──────────────────────────────────────────
echo ""
echo "[vgc-agent-kit] Kiểm tra Token A..."

VERIFY_OK=true
if command -v gh &>/dev/null; then
    if gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
        echo "  ✓ Agent Kit (vgcorpvn/vgc-agent-kit)"
    else
        echo "  ✗ Agent Kit — KHÔNG truy cập được"
        VERIFY_OK=false
    fi
    if gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
        echo "  ✓ Workspace (vgcorpvn/vgc-agent-workspace)"
    else
        echo "  ✗ Workspace — KHÔNG truy cập được"
        VERIFY_OK=false
    fi
fi

if [ "$VERIFY_OK" = false ]; then
    echo "[vgc-agent-kit] ERROR: Token A không đủ quyền."
    exit 1
fi

echo ""

# ──────────────────────────────────────────
# Step 6: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
CLEAN_URL="https://github.com/vgcorpvn/vgc-agent-kit.git"

if [ -d "$VGC_DIR/.git" ]; then
    echo "[vgc-agent-kit] Repo đã tồn tại — pulling latest..."
    CURRENT_URL="$(git -C "$VGC_DIR" remote get-url origin 2>/dev/null || echo "")"
    if [ "$CURRENT_URL" != "$CLEAN_URL" ]; then
        git -C "$VGC_DIR" remote set-url origin "$CLEAN_URL"
    fi
    git -C "$VGC_DIR" checkout main 2>/dev/null || true
    git -C "$VGC_DIR" pull --ff-only origin main || echo "[vgc-agent-kit] WARNING: Pull thất bại."
elif [ -d "$VGC_DIR" ]; then
    echo "[vgc-agent-kit] Thư mục $VGC_DIR tồn tại nhưng không phải git repo."
    read -rp "Ghi đè? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "[vgc-agent-kit] Huỷ bỏ."
        exit 0
    fi
    rm -rf "$VGC_DIR"
    git clone --quiet "$CLEAN_URL" "$VGC_DIR"
    echo "[vgc-agent-kit] Clone thành công."
else
    git clone --quiet "$CLEAN_URL" "$VGC_DIR"
    echo "[vgc-agent-kit] Clone thành công."
fi

# ──────────────────────────────────────────
# Step 7: Clone/update workspace
# ──────────────────────────────────────────
CLEAN_WS_URL="https://github.com/vgcorpvn/vgc-agent-workspace.git"

if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "[vgc-agent-kit] Workspace đã tồn tại — pulling latest..."
    WS_URL="$(git -C "$WORKSPACE_DIR" remote get-url origin 2>/dev/null || echo "")"
    if [ "$WS_URL" != "$CLEAN_WS_URL" ]; then
        git -C "$WORKSPACE_DIR" remote set-url origin "$CLEAN_WS_URL"
    fi
    git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Workspace pull skipped."
elif [ -d "$WORKSPACE_DIR" ]; then
    read -rp "Workspace tồn tại nhưng không phải git repo. Ghi đè? (y/N): " overwrite_ws
    if [[ "$overwrite_ws" != "y" && "$overwrite_ws" != "Y" ]]; then
        echo "[vgc-agent-kit] Bỏ qua workspace setup."
    else
        rm -rf "$WORKSPACE_DIR"
        git clone --quiet "$CLEAN_WS_URL" "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Workspace clone thành công."
    fi
else
    git clone --quiet "$CLEAN_WS_URL" "$WORKSPACE_DIR"
    echo "[vgc-agent-kit] Workspace clone thành công."
fi

# ──────────────────────────────────────────
# Step 8: Token B — mobile repo (read-only, optional)
# ──────────────────────────────────────────
SKIP_MOBILE=false

if command -v gh &>/dev/null && gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
    echo "[vgc-agent-kit] Token A đã truy cập được mobile repo — bỏ qua Token B."
    mkdir -p "$CONFIG_DIR"
    gh auth token -h github.com 2>/dev/null > "$MOBILE_TOKEN_FILE" || true
    chmod 600 "$MOBILE_TOKEN_FILE" 2>/dev/null || true
    SKIP_MOBILE=true
fi

if [ "$SKIP_MOBILE" = false ] && [ -f "$MOBILE_TOKEN_FILE" ]; then
    EXISTING=$(cat "$MOBILE_TOKEN_FILE" 2>/dev/null || echo "")
    if [ -n "$EXISTING" ] && GH_TOKEN="$EXISTING" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
        echo "[vgc-agent-kit] Token B (mobile) còn hợp lệ — dùng lại."
        SKIP_MOBILE=true
    fi
fi

if [ "$SKIP_MOBILE" = false ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  Token B — cho mobile repo (read-only, optional)        │"
    echo "│                                                         │"
    echo "│  Quyền: repo:read cho vgcorpvn/mobile.vhandicap.com    │"
    echo "│  Enter để bỏ qua                                       │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Nhập Token B (Enter để bỏ qua): " TOKEN_B
    echo ""

    if [ -n "$TOKEN_B" ]; then
        if GH_TOKEN="$TOKEN_B" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            mkdir -p "$CONFIG_DIR"
            echo "$TOKEN_B" > "$MOBILE_TOKEN_FILE"
            chmod 600 "$MOBILE_TOKEN_FILE"
            echo "[vgc-agent-kit] ✓ Token B OK — mobile repo truy cập được."
        else
            echo "[vgc-agent-kit] WARNING: Token B không truy cập được mobile repo."
        fi
    else
        echo "[vgc-agent-kit] Bỏ qua Token B."
    fi
fi

echo ""

# ──────────────────────────────────────────
# Step 9: Symlink skills
# ──────────────────────────────────────────
mkdir -p "$SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$SKILLS_DIR/$skill_name"
    echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# ──────────────────────────────────────────
# Step 10: Add update alias
# ──────────────────────────────────────────
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

eval "$ALIAS_LINE" 2>/dev/null || true

echo ""
echo "======================================"
echo "  Setup hoàn tất!"
echo "======================================"
echo ""
echo "  Skills location: $SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auth:"
echo "    Token A: gh CLI (kit + workspace)"
if [ -f "$MOBILE_TOKEN_FILE" ]; then
echo "    Token B: $MOBILE_TOKEN_FILE (mobile, read-only)"
else
echo "    Token B: không có"
fi
echo "  Manual update:   vgc-agent-kit-update-codex"
echo ""
