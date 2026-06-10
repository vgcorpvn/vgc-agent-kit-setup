#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script thất bại tại dòng $LINENO (exit code $?)" >&2' ERR

VGC_DIR="$HOME/.vgc-agent-kit"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
WORKSPACE_DIR="$HOME/.vgc-agent-workspace"

# Never prompt for credentials — fail silently instead of exposing tokens
export GIT_TERMINAL_PROMPT=0

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
if [ ! -d "$HOME/.claude" ]; then
    echo "[vgc-agent-kit] ERROR: Thư mục ~/.claude không tồn tại."
    echo "[vgc-agent-kit] Vui lòng cài Claude Code trước: https://claude.ai/download"
    exit 1
fi

echo "[vgc-agent-kit] Claude Code OK."

# Step 3: Check existing installation — reuse if already cloned (e.g. by Codex setup)
SKIP_CLONE=false
if [ -d "$VGC_DIR" ]; then
    if [ -d "$VGC_DIR/.git" ]; then
        echo "[vgc-agent-kit] Repo đã tồn tại tại $VGC_DIR — dùng lại (skip clone)."
        git -C "$VGC_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Pull skipped (offline hoặc token hết hạn)."
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
    echo "Cần GitHub Personal Access Token (PAT) với quyền repo:read+write."
    echo "Token này dùng cho cả vgc-agent-kit và vgc-agent-workspace."
    echo "Tạo tại: https://github.com/settings/tokens"
    echo ""
    read -rsp "Nhập GitHub token: " GITHUB_TOKEN
    echo ""

    if [ -z "$GITHUB_TOKEN" ]; then
        echo "[vgc-agent-kit] ERROR: Token không được để trống."
        exit 1
    fi

    # Step 5: Clone repo (token in URL for clone only)
    echo "[vgc-agent-kit] Đang clone repository..."
    git clone --quiet "https://${GITHUB_TOKEN}@github.com/vgcorpvn/vgc-agent-kit.git" "$VGC_DIR" || {
        echo "[vgc-agent-kit] ERROR: Clone thất bại. Kiểm tra lại token và quyền truy cập repo."
        exit 1
    }

    echo "[vgc-agent-kit] Clone thành công."
fi

# Step 6b: Check/install gh CLI
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
    echo "[vgc-agent-kit] WARNING: gh CLI không có. Tạo PR thủ công khi dùng /vgc-agent-kit-publish."
fi

# Step 6c: Clone workspace repo
SKIP_WORKSPACE=false
if [ -d "$WORKSPACE_DIR" ]; then
    if [ -d "$WORKSPACE_DIR/.git" ]; then
        echo "[vgc-agent-kit] Workspace repo đã tồn tại — dùng lại."
        git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Workspace pull skipped."
        SKIP_WORKSPACE=true
    else
        echo "[vgc-agent-kit] Thư mục $WORKSPACE_DIR tồn tại nhưng không phải git repo."
        read -rp "Ghi đè? (y/N): " overwrite_ws
        if [[ "$overwrite_ws" != "y" && "$overwrite_ws" != "Y" ]]; then
            echo "[vgc-agent-kit] Bỏ qua workspace setup."
            SKIP_WORKSPACE=true
        else
            rm -rf "$WORKSPACE_DIR"
        fi
    fi
fi

if [ "$SKIP_WORKSPACE" = false ]; then
    # Reuse Token A for workspace (same token, read+write)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        WORKSPACE_TOKEN="$GITHUB_TOKEN"
        echo "[vgc-agent-kit] Dùng cùng token cho workspace (read+write)."
    else
        echo ""
        echo "Cần GitHub token (PAT) với quyền repo:read+write cho workspace."
        read -rsp "Nhập GitHub token: " WORKSPACE_TOKEN
        echo ""
    fi

    if [ -z "$WORKSPACE_TOKEN" ]; then
        echo "[vgc-agent-kit] WARNING: Token workspace trống. Bỏ qua workspace setup."
    else
        echo "[vgc-agent-kit] Đang clone workspace..."
        git clone --quiet "https://${WORKSPACE_TOKEN}@github.com/vgcorpvn/vgc-agent-workspace.git" "$WORKSPACE_DIR" || {
            echo "[vgc-agent-kit] WARNING: Clone workspace thất bại. Kiểm tra token và quyền truy cập."
        }

        if [ -d "$WORKSPACE_DIR/.git" ]; then
            echo "[vgc-agent-kit] Workspace clone thành công."

            # Auth gh CLI with workspace token
            if command -v gh &>/dev/null; then
                echo "$WORKSPACE_TOKEN" | gh auth login --with-token 2>/dev/null || {
                    echo "[vgc-agent-kit] WARNING: gh auth login thất bại. Tạo PR thủ công."
                }
                echo "[vgc-agent-kit] gh CLI đã auth."
            fi
        fi
    fi
fi

# Step 6d: Store mobile repo token for gh api access (optional)
SKIP_MOBILE=false
if command -v gh &>/dev/null; then
    if gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
        echo "[vgc-agent-kit] Mobile repo đã truy cập được — skip token."
        SKIP_MOBILE=true
    fi
fi

if [ "$SKIP_MOBILE" = false ]; then
    echo ""
    echo "Cần GitHub Token thứ 2 (PAT) với quyền repo:read cho mobile repo."
    echo "Token này dùng để agent đọc screen-index.json và source code."
    echo "(Bỏ qua nếu không cần discover-screen skill)"
    echo ""
    read -rsp "Nhập GitHub token (mobile, Enter để bỏ qua): " MOBILE_TOKEN
    echo ""

    if [ -n "$MOBILE_TOKEN" ]; then
        git config --global credential.helper store
        printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
            "$MOBILE_TOKEN" "$MOBILE_TOKEN" \
            | git credential approve 2>/dev/null || true
        echo "[vgc-agent-kit] Mobile repo token đã lưu."
    fi
fi

# Step 7: Symlink skills to ~/.claude/skills/
mkdir -p "$CLAUDE_SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$CLAUDE_SKILLS_DIR/$skill_name"
    echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# Step 8: Add alias
SHELL_RC="$HOME/.zshrc"
if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

ALIAS_LINE="alias vgc-agent-kit-update-claude=\"$VGC_DIR/scripts/vgc-agent-kit-update-claude.sh\""

if ! grep -q "vgc-agent-kit-update-claude" "$SHELL_RC" 2>/dev/null; then
    {
        echo ""
        echo "# VGC Agent Kit (Claude Code)"
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
echo "  Skills location: $CLAUDE_SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auto-sync:       Pull tự động mỗi khi dùng skill"
echo "  Manual update:   vgc-agent-kit-update-claude"
echo ""
echo "  Khởi động lại Claude Code để load skills."
echo "  Gõ / để xem danh sách skills."
echo ""
