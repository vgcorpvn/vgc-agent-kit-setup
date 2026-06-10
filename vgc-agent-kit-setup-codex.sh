#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script thất bại tại dòng $LINENO (exit code $?)" >&2' ERR

VGC_DIR="$HOME/.vgc-agent-kit"
SKILLS_DIR="$HOME/.agents/skills"
WORKSPACE_DIR="$HOME/.vgc-agent-workspace"

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

# Step 5b: Check/install gh CLI
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

# Step 5c: Clone workspace repo
SKIP_WORKSPACE=false
if [ -d "$WORKSPACE_DIR" ]; then
    if [ -d "$WORKSPACE_DIR/.git" ]; then
        echo "[vgc-agent-kit] Workspace repo đã tồn tại — dùng lại."
        git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || true
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
    echo ""
    echo "Cần GitHub Token thứ 2 (PAT) với quyền repo:read+write cho workspace."
    echo "Token này dùng để push output lên vgc-agent-workspace."
    echo ""
    read -rsp "Nhập GitHub token (workspace): " WORKSPACE_TOKEN
    echo ""

    if [ -z "$WORKSPACE_TOKEN" ]; then
        echo "[vgc-agent-kit] WARNING: Token workspace trống. Bỏ qua workspace setup."
    else
        WORKSPACE_URL="https://${WORKSPACE_TOKEN}@github.com/vgcorpvn/vgc-agent-workspace.git"
        echo "[vgc-agent-kit] Đang clone workspace..."
        git clone --quiet "$WORKSPACE_URL" "$WORKSPACE_DIR" || {
            echo "[vgc-agent-kit] WARNING: Clone workspace thất bại. Kiểm tra token và quyền truy cập."
        }

        if [ -d "$WORKSPACE_DIR/.git" ]; then
            echo "[vgc-agent-kit] Workspace clone thành công."

            # Store workspace credentials
            git -C "$WORKSPACE_DIR" config credential.helper store
            echo "https://${WORKSPACE_TOKEN}@github.com" \
                | git -C "$WORKSPACE_DIR" credential approve 2>/dev/null || true

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

# Step 6: Symlink skills
mkdir -p "$SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$SKILLS_DIR/$skill_name"
    echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# Step 7: Add alias
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
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auto-sync:       Pull tự động mỗi khi dùng skill"
echo "  Manual update:   vgc-agent-kit-update-codex"
echo ""