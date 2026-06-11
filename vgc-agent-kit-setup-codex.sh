#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script failed at line $LINENO (exit code $?)" >&2' ERR

VGC_ROOT="$HOME/.vgc"
VGC_DIR="$VGC_ROOT/agent-kit"
SKILLS_DIR="$HOME/.agents/skills"
WORKSPACE_DIR="$VGC_ROOT/agent-workspace"
CONFIG_DIR="$VGC_ROOT/config"
MOBILE_TOKEN_FILE="$CONFIG_DIR/mobile-token"

export GIT_TERMINAL_PROMPT=0

mkdir -p "$VGC_ROOT"

echo "======================================"
echo "  VGC Agent Kit — Setup (Codex CLI)"
echo "======================================"
echo ""

# ──────────────────────────────────────────
# Step 1: Check git
# ──────────────────────────────────────────
if ! command -v git &>/dev/null; then
    echo "[vgc-agent-kit] Git is not installed."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "[vgc-agent-kit] Installing Git via Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        echo ""
        echo "Please complete the Xcode Command Line Tools installation in the popup,"
        echo "then re-run this script."
        exit 1
    else
        echo "[vgc-agent-kit] Please install Git:"
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
    echo "[vgc-agent-kit] GitHub CLI (gh) not found. Installing..."
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            brew install gh 2>/dev/null || {
                echo "[vgc-agent-kit] WARNING: Failed to install gh via brew."
                echo "[vgc-agent-kit] Install manually: https://cli.github.com/"
            }
        else
            echo "[vgc-agent-kit] WARNING: Homebrew not installed. Install gh manually:"
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
            echo "[vgc-agent-kit] WARNING: Could not install gh automatically. Install manually:"
            echo "  https://cli.github.com/"
        fi
    fi
fi

if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] gh CLI OK: $(gh --version | head -1)"
else
    echo "[vgc-agent-kit] WARNING: gh CLI not available. Some skills will not work."
fi

# ──────────────────────────────────────────
# Step 3: Authenticate gh CLI — kit + workspace (read+write)
# ──────────────────────────────────────────
NEED_MAIN_TOKEN=true

if command -v gh &>/dev/null; then
    if gh auth status -h github.com &>/dev/null; then
        echo ""
        echo "[vgc-agent-kit] gh CLI already authenticated."

        REPOS_OK=true
        if ! gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
            REPOS_OK=false
        fi
        if ! gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
            REPOS_OK=false
        fi

        if [ "$REPOS_OK" = true ]; then
            echo "[vgc-agent-kit] Token access OK — reusing."
            NEED_MAIN_TOKEN=false
        else
            echo "[vgc-agent-kit] Token lacks required permissions — need a new token."
        fi
    fi
fi

if [ "$NEED_MAIN_TOKEN" = true ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│  GitHub PAT — for kit + workspace repos (read+write)   │"
    echo "│                                                        │"
    echo "│  Minimum scopes: repo, read:org                        │"
    echo "│  Token must have access to:                            │"
    echo "│    • vgcorpvn/vgc-agent-kit       (read+write)         │"
    echo "│    • vgcorpvn/vgc-agent-workspace (read+write)         │"
    echo "│                                                        │"
    echo "│  Create at: https://github.com/settings/tokens         │"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Enter GitHub PAT: " MAIN_TOKEN
    echo ""

    if [ -z "$MAIN_TOKEN" ]; then
        echo "[vgc-agent-kit] ERROR: Token cannot be empty."
        exit 1
    fi

    if command -v gh &>/dev/null; then
        echo "[vgc-agent-kit] Authenticating gh CLI..."
        if echo "$MAIN_TOKEN" | gh auth login -h github.com --with-token 2>/dev/null; then
            echo "[vgc-agent-kit] gh auth OK."
        else
            echo "[vgc-agent-kit] ERROR: gh auth login failed."
            exit 1
        fi
    fi
fi

# ──────────────────────────────────────────
# Step 4: Setup gh as git credential helper
# ──────────────────────────────────────────
if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] Syncing credentials: gh → git..."
    gh auth setup-git -h github.com 2>/dev/null || true
    echo "[vgc-agent-kit] git credential helper = gh CLI."
fi

# ──────────────────────────────────────────
# Step 5: Verify repo access
# ──────────────────────────────────────────
echo ""
echo "[vgc-agent-kit] Verifying repo access..."

VERIFY_OK=true
if command -v gh &>/dev/null; then
    if gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
        echo "  ✓ Agent Kit (vgcorpvn/vgc-agent-kit)"
    else
        echo "  ✗ Agent Kit — access denied"
        VERIFY_OK=false
    fi
    if gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
        echo "  ✓ Workspace (vgcorpvn/vgc-agent-workspace)"
    else
        echo "  ✗ Workspace — access denied"
        VERIFY_OK=false
    fi
fi

if [ "$VERIFY_OK" = false ]; then
    echo "[vgc-agent-kit] ERROR: Token lacks required permissions."
    exit 1
fi

echo ""

# ──────────────────────────────────────────
# Step 6: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
REPO_URL="https://github.com/vgcorpvn/vgc-agent-kit.git"

if [ -d "$VGC_DIR/.git" ]; then
    echo "[vgc-agent-kit] Repo already exists — pulling latest..."
    git -C "$VGC_DIR" checkout main 2>/dev/null || true
    git -C "$VGC_DIR" pull --ff-only origin main || echo "[vgc-agent-kit] WARNING: Pull failed."
elif [ -d "$VGC_DIR" ]; then
    echo "[vgc-agent-kit] Directory $VGC_DIR exists but is not a git repo."
    read -rp "Overwrite? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "[vgc-agent-kit] Aborted."
        exit 0
    fi
    rm -rf "$VGC_DIR"
    git clone --quiet "$REPO_URL" "$VGC_DIR"
    echo "[vgc-agent-kit] Cloned successfully."
else
    git clone --quiet "$REPO_URL" "$VGC_DIR"
    echo "[vgc-agent-kit] Cloned successfully."
fi

# ──────────────────────────────────────────
# Step 7: Clone/update workspace
# ──────────────────────────────────────────
WORKSPACE_URL="https://github.com/vgcorpvn/vgc-agent-workspace.git"

if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "[vgc-agent-kit] Workspace already exists — pulling latest..."
    git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Workspace pull skipped."
elif [ -d "$WORKSPACE_DIR" ]; then
    read -rp "Workspace exists but is not a git repo. Overwrite? (y/N): " overwrite_ws
    if [[ "$overwrite_ws" != "y" && "$overwrite_ws" != "Y" ]]; then
        echo "[vgc-agent-kit] Skipping workspace setup."
    else
        rm -rf "$WORKSPACE_DIR"
        git clone --quiet "$WORKSPACE_URL" "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Workspace cloned successfully."
    fi
else
    git clone --quiet "$WORKSPACE_URL" "$WORKSPACE_DIR"
    echo "[vgc-agent-kit] Workspace cloned successfully."
fi

# ──────────────────────────────────────────
# Step 8: Mobile token (optional) — mobile repo (read-only, optional)
# ──────────────────────────────────────────
SKIP_MOBILE=false

if command -v gh &>/dev/null && gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
    echo "[vgc-agent-kit] Token already has mobile repo access — no separate token needed."
    mkdir -p "$CONFIG_DIR"
    gh auth token -h github.com 2>/dev/null > "$MOBILE_TOKEN_FILE" || true
    chmod 600 "$MOBILE_TOKEN_FILE" 2>/dev/null || true
    SKIP_MOBILE=true
fi

if [ "$SKIP_MOBILE" = false ] && [ -f "$MOBILE_TOKEN_FILE" ]; then
    EXISTING=$(cat "$MOBILE_TOKEN_FILE" 2>/dev/null || echo "")
    if [ -n "$EXISTING" ] && GH_TOKEN="$EXISTING" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
        echo "[vgc-agent-kit] Existing mobile token is valid — reusing."
        SKIP_MOBILE=true
    fi
fi

if [ "$SKIP_MOBILE" = false ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│  Mobile token — for mobile repo (read-only, optional)  │"
    echo "│                                                        │"
    echo "│  Scope: repo:read for vgcorpvn/mobile.vhandicap.com   │"
    echo "│  Press Enter to skip if not needed                     │"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Enter mobile token (Enter to skip): " MOBILE_PAT
    echo ""

    if [ -n "$MOBILE_PAT" ]; then
        if GH_TOKEN="$MOBILE_PAT" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            mkdir -p "$CONFIG_DIR"
            echo "$MOBILE_PAT" > "$MOBILE_TOKEN_FILE"
            chmod 600 "$MOBILE_TOKEN_FILE"
            echo "[vgc-agent-kit] ✓ Mobile token OK."
        else
            echo "[vgc-agent-kit] WARNING: Mobile token is invalid."
        fi
    else
        echo "[vgc-agent-kit] Skipped mobile token."
    fi
fi

echo ""

# ──────────────────────────────────────────
# Step 9: Symlink skills
# ──────────────────────────────────────────
mkdir -p "$SKILLS_DIR"

# Remove stale symlinks (skills deleted/renamed in repo)
for link in "$SKILLS_DIR"/vgc-agent-kit-*; do
    [ -L "$link" ] || continue
    target="$(readlink "$link")"
    if [[ "$target" == "$VGC_DIR/skills/"* ]] && [ ! -d "$target" ]; then
        rm "$link"
        echo "[vgc-agent-kit] Removed stale skill: $(basename "$link")"
    fi
done

for skill_dir in "$VGC_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] || continue
    rm -f "$SKILLS_DIR/$skill_name"
    ln -s "$skill_dir" "$SKILLS_DIR/$skill_name"
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
echo "  Setup complete!"
echo "======================================"
echo ""
echo "  Skills location: $SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auth:"
echo "    gh CLI:        authenticated (kit + workspace)"
if [ -f "$MOBILE_TOKEN_FILE" ]; then
echo "    Mobile token:  $MOBILE_TOKEN_FILE"
else
echo "    Mobile token:  not configured"
fi
echo "  Manual update:   vgc-agent-kit-update-codex"
echo ""
