#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script thất bại tại dòng $LINENO (exit code $?)" >&2' ERR

VGC_ROOT="$HOME/.vgc"
VGC_DIR="$VGC_ROOT/agent-kit"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
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
echo "  VGC Agent Kit — Setup (Claude Code)"
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
# Step 2: Check Claude Code installed
# ──────────────────────────────────────────
if [ ! -d "$HOME/.claude" ]; then
    echo "[vgc-agent-kit] ERROR: Thư mục ~/.claude không tồn tại."
    echo "[vgc-agent-kit] Vui lòng cài Claude Code trước: https://claude.ai/download"
    exit 1
fi

echo "[vgc-agent-kit] Claude Code OK."

# ──────────────────────────────────────────
# Step 3: Check/install gh CLI
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
# Step 4: Token A — kit + workspace (read+write)
# ──────────────────────────────────────────
# Token A is used for:
#   - gh auth (gh api, gh pr create for kit + workspace repos)
#   - git clone/pull/push (via gh credential helper)

NEED_TOKEN_A=true

if command -v gh &>/dev/null; then
    if gh auth status -h github.com &>/dev/null; then
        echo ""
        echo "[vgc-agent-kit] gh CLI đã authenticated."

        REPOS_OK=true
        if ! gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] WARNING: Token hiện tại không truy cập được vgc-agent-kit repo."
            REPOS_OK=false
        fi
        if ! gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] WARNING: Token hiện tại không truy cập được vgc-agent-workspace repo."
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

    if [[ ! "$TOKEN_A" =~ ^(ghp_|github_pat_) ]]; then
        echo "[vgc-agent-kit] WARNING: Token không bắt đầu bằng ghp_ hoặc github_pat_."
    fi

    if command -v gh &>/dev/null; then
        echo "[vgc-agent-kit] Đang xác thực gh CLI với Token A..."
        if echo "$TOKEN_A" | gh auth login -h github.com --with-token 2>/dev/null; then
            echo "[vgc-agent-kit] gh auth OK."
        else
            echo "[vgc-agent-kit] ERROR: gh auth login thất bại. Token không hợp lệ hoặc hết hạn."
            exit 1
        fi
    fi
fi

# ──────────────────────────────────────────
# Step 5: Setup gh as git credential helper
# ──────────────────────────────────────────
if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] Đồng bộ credentials: gh → git..."
    gh auth setup-git -h github.com 2>/dev/null || {
        echo "[vgc-agent-kit] WARNING: gh auth setup-git thất bại."
    }
    echo "[vgc-agent-kit] git credential helper = gh CLI."
fi

# ──────────────────────────────────────────
# Step 6: Verify Token A repo access
# ──────────────────────────────────────────
echo ""
echo "[vgc-agent-kit] Kiểm tra Token A..."

verify_repo() {
    local repo="$1"
    local label="$2"
    local required="$3"
    local token="${4:-}"

    local result
    if [ -n "$token" ]; then
        result=$(GH_TOKEN="$token" gh api "repos/$repo" --jq '.name' 2>/dev/null) || true
    elif command -v gh &>/dev/null; then
        result=$(gh api "repos/$repo" --jq '.name' 2>/dev/null) || true
    fi

    if [ -n "$result" ]; then
        echo "  ✓ $label ($repo)"
        return 0
    else
        if [ "$required" = true ]; then
            echo "  ✗ $label ($repo) — KHÔNG truy cập được"
            return 1
        else
            echo "  - $label ($repo) — không truy cập được (optional)"
            return 0
        fi
    fi
}

VERIFY_OK=true
verify_repo "vgcorpvn/vgc-agent-kit" "Agent Kit" true || VERIFY_OK=false
verify_repo "vgcorpvn/vgc-agent-workspace" "Workspace" true || VERIFY_OK=false

if [ "$VERIFY_OK" = false ]; then
    echo ""
    echo "[vgc-agent-kit] ERROR: Token A không đủ quyền truy cập repos bắt buộc."
    echo "[vgc-agent-kit] Kiểm tra token có quyền 'repo' và được mời vào org vgcorpvn."
    exit 1
fi

echo ""

# ──────────────────────────────────────────
# Step 7: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
if [ -d "$VGC_DIR/.git" ]; then
    echo "[vgc-agent-kit] Repo đã tồn tại tại $VGC_DIR — pulling latest..."

    CURRENT_URL="$(git -C "$VGC_DIR" remote get-url origin 2>/dev/null || echo "")"
    CLEAN_URL="https://github.com/vgcorpvn/vgc-agent-kit.git"
    if [ "$CURRENT_URL" != "$CLEAN_URL" ]; then
        git -C "$VGC_DIR" remote set-url origin "$CLEAN_URL"
        echo "[vgc-agent-kit] Remote URL cập nhật (bỏ embedded token, dùng gh credential helper)."
    fi

    git -C "$VGC_DIR" checkout main 2>/dev/null || true
    git -C "$VGC_DIR" pull --ff-only origin main || {
        echo "[vgc-agent-kit] WARNING: Pull thất bại. Tiếp tục với version hiện tại."
    }
elif [ -d "$VGC_DIR" ]; then
    echo "[vgc-agent-kit] Thư mục $VGC_DIR tồn tại nhưng không phải git repo."
    read -rp "Ghi đè? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "[vgc-agent-kit] Huỷ bỏ."
        exit 0
    fi
    rm -rf "$VGC_DIR"
    echo "[vgc-agent-kit] Đang clone repository..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-kit.git" "$VGC_DIR"
    echo "[vgc-agent-kit] Clone thành công."
else
    echo "[vgc-agent-kit] Đang clone repository..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-kit.git" "$VGC_DIR"
    echo "[vgc-agent-kit] Clone thành công."
fi

# ──────────────────────────────────────────
# Step 8: Clone/update workspace
# ──────────────────────────────────────────
if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "[vgc-agent-kit] Workspace đã tồn tại — pulling latest..."

    WS_URL="$(git -C "$WORKSPACE_DIR" remote get-url origin 2>/dev/null || echo "")"
    CLEAN_WS_URL="https://github.com/vgcorpvn/vgc-agent-workspace.git"
    if [ "$WS_URL" != "$CLEAN_WS_URL" ]; then
        git -C "$WORKSPACE_DIR" remote set-url origin "$CLEAN_WS_URL"
        echo "[vgc-agent-kit] Workspace remote URL cập nhật (dùng gh credential helper)."
    fi

    git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Workspace pull skipped."
elif [ -d "$WORKSPACE_DIR" ]; then
    echo "[vgc-agent-kit] Thư mục $WORKSPACE_DIR tồn tại nhưng không phải git repo."
    read -rp "Ghi đè? (y/N): " overwrite_ws
    if [[ "$overwrite_ws" != "y" && "$overwrite_ws" != "Y" ]]; then
        echo "[vgc-agent-kit] Bỏ qua workspace setup."
    else
        rm -rf "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Đang clone workspace..."
        git clone --quiet "https://github.com/vgcorpvn/vgc-agent-workspace.git" "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Workspace clone thành công."
    fi
else
    echo "[vgc-agent-kit] Đang clone workspace..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-workspace.git" "$WORKSPACE_DIR"
    echo "[vgc-agent-kit] Workspace clone thành công."
fi

# ──────────────────────────────────────────
# Step 9: Token B — mobile repo (read-only, optional)
# ──────────────────────────────────────────
# Token B is separate from Token A (least privilege).
# Stored in ~/.vgc/config/mobile-token (outside git repo)
# Skills read this file and use: GH_TOKEN=$(cat ~/.vgc/config/mobile-token) gh api ...

SKIP_MOBILE=false

# Check if Token A already has mobile access
if command -v gh &>/dev/null && gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
    echo "[vgc-agent-kit] Token A đã truy cập được mobile repo."
    echo "[vgc-agent-kit] Bỏ qua Token B (không cần token riêng)."
    # Save Token A as mobile token so skills have a consistent path
    mkdir -p "$CONFIG_DIR"
    gh auth token -h github.com 2>/dev/null > "$MOBILE_TOKEN_FILE" || true
    chmod 600 "$MOBILE_TOKEN_FILE" 2>/dev/null || true
    SKIP_MOBILE=true
fi

# Check if existing Token B still works
if [ "$SKIP_MOBILE" = false ] && [ -f "$MOBILE_TOKEN_FILE" ]; then
    EXISTING_MOBILE_TOKEN=$(cat "$MOBILE_TOKEN_FILE" 2>/dev/null || echo "")
    if [ -n "$EXISTING_MOBILE_TOKEN" ]; then
        if GH_TOKEN="$EXISTING_MOBILE_TOKEN" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] Token B (mobile) còn hợp lệ — dùng lại."
            SKIP_MOBILE=true
        else
            echo "[vgc-agent-kit] Token B (mobile) đã hết hạn — cần nhập lại."
        fi
    fi
fi

if [ "$SKIP_MOBILE" = false ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  Token B — cho mobile repo (read-only, optional)        │"
    echo "│                                                         │"
    echo "│  Quyền: repo:read cho vgcorpvn/mobile.vhandicap.com    │"
    echo "│  Dùng cho skill /discover-screen (đọc screen-index)     │"
    echo "│  Enter để bỏ qua nếu không cần                         │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Nhập Token B (Enter để bỏ qua): " TOKEN_B
    echo ""

    if [ -n "$TOKEN_B" ]; then
        # Verify Token B can access mobile repo
        if GH_TOKEN="$TOKEN_B" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            mkdir -p "$CONFIG_DIR"
            echo "$TOKEN_B" > "$MOBILE_TOKEN_FILE"
            chmod 600 "$MOBILE_TOKEN_FILE"
            echo "[vgc-agent-kit] Token B đã lưu và verify OK."
            echo ""
            echo "[vgc-agent-kit] Kiểm tra Token B..."
            verify_repo "vgcorpvn/mobile.vhandicap.com" "Mobile repo" false "$TOKEN_B"
        else
            echo "[vgc-agent-kit] WARNING: Token B không truy cập được mobile repo."
            echo "[vgc-agent-kit] Skill /discover-screen sẽ không hoạt động."
        fi
    else
        echo "[vgc-agent-kit] Bỏ qua Token B. Skill /discover-screen sẽ không hoạt động."
    fi
fi

echo ""

# ──────────────────────────────────────────
# Step 10: Symlink skills to ~/.claude/skills/
# ──────────────────────────────────────────
mkdir -p "$CLAUDE_SKILLS_DIR"

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    ln -sf "$skill_dir" "$CLAUDE_SKILLS_DIR/$skill_name"
    echo "[vgc-agent-kit] Linked skill: $skill_name"
done

# ──────────────────────────────────────────
# Step 11: Add update alias
# ──────────────────────────────────────────
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

# ──────────────────────────────────────────
# Done
# ──────────────────────────────────────────
echo ""
echo "======================================"
echo "  Setup hoàn tất!"
echo "======================================"
echo ""
echo "  Skills location: $CLAUDE_SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auth:"
echo "    Token A: gh CLI (kit + workspace, đồng bộ git + gh api)"
if [ -f "$MOBILE_TOKEN_FILE" ]; then
echo "    Token B: $MOBILE_TOKEN_FILE (mobile, read-only)"
else
echo "    Token B: không có (skill /discover-screen disabled)"
fi
echo "  Auto-sync:       Pull tự động mỗi khi dùng skill"
echo "  Manual update:   vgc-agent-kit-update-claude"
echo ""
echo "  Khởi động lại Claude Code để load skills."
echo "  Gõ / để xem danh sách skills."
echo ""
