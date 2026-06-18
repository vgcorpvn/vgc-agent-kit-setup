#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[vgc-agent-kit] ERROR: Script failed at line $LINENO (exit code $?)" >&2' ERR

VGC_ROOT="$HOME/.vgc"
VGC_DIR="$VGC_ROOT/agent-kit"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
WORKSPACE_DIR="$VGC_ROOT/agent-workspace"
CONFIG_DIR="$VGC_ROOT/config"
SCOUT_TOKEN_FILE="$CONFIG_DIR/scout-token"

export GIT_TERMINAL_PROMPT=0

mkdir -p "$VGC_ROOT"

echo "======================================"
echo "  VGC Agent Kit — Setup (Claude Code)"
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
# Step 2: Check Claude Code installed
# ──────────────────────────────────────────
if [ ! -d "$HOME/.claude" ]; then
    echo "[vgc-agent-kit] ERROR: ~/.claude directory not found."
    echo "[vgc-agent-kit] Please install Claude Code first: https://claude.ai/download"
    exit 1
fi

echo "[vgc-agent-kit] Claude Code OK."

# ──────────────────────────────────────────
# Step 3: Check/install gh CLI
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
# Step 4: Authenticate gh CLI — kit + workspace (read+write)
# ──────────────────────────────────────────
# Used for:
#   - gh auth (gh api, gh pr create for kit + workspace repos)
#   - git clone/pull/push (via gh credential helper)

NEED_MAIN_TOKEN=true

if command -v gh &>/dev/null; then
    if gh auth status -h github.com &>/dev/null; then
        echo ""
        echo "[vgc-agent-kit] gh CLI already authenticated."

        REPOS_OK=true
        if ! gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] WARNING: Current token cannot access vgc-agent-kit repo."
            REPOS_OK=false
        fi
        if ! gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] WARNING: Current token cannot access vgc-agent-workspace repo."
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

    if [[ ! "$MAIN_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
        echo "[vgc-agent-kit] WARNING: Token does not start with ghp_ or github_pat_."
    fi

    if command -v gh &>/dev/null; then
        echo "[vgc-agent-kit] Authenticating gh CLI..."
        if echo "$MAIN_TOKEN" | gh auth login -h github.com --with-token 2>/dev/null; then
            echo "[vgc-agent-kit] gh auth OK."
        else
            echo "[vgc-agent-kit] ERROR: gh auth login failed. Token may be invalid or expired."
            exit 1
        fi
    fi
fi

# ──────────────────────────────────────────
# Step 5: Setup gh as git credential helper
# ──────────────────────────────────────────
if command -v gh &>/dev/null; then
    echo "[vgc-agent-kit] Syncing credentials: gh → git..."
    gh auth setup-git -h github.com 2>/dev/null || {
        echo "[vgc-agent-kit] WARNING: gh auth setup-git failed."
    }
    echo "[vgc-agent-kit] git credential helper = gh CLI."
fi

# ──────────────────────────────────────────
# Step 6: Verify repo access
# ──────────────────────────────────────────
echo ""
echo "[vgc-agent-kit] Verifying repo access..."

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
            echo "  ✗ $label ($repo) — access denied"
            return 1
        else
            echo "  - $label ($repo) — no access (optional)"
            return 0
        fi
    fi
}

VERIFY_OK=true
verify_repo "vgcorpvn/vgc-agent-kit" "Agent Kit" true || VERIFY_OK=false
verify_repo "vgcorpvn/vgc-agent-workspace" "Workspace" true || VERIFY_OK=false

if [ "$VERIFY_OK" = false ]; then
    echo ""
    echo "[vgc-agent-kit] ERROR: Token lacks access to required repos."
    echo "[vgc-agent-kit] Ensure token has 'repo' scope and account is invited to org vgcorpvn."
    exit 1
fi

echo ""

# ──────────────────────────────────────────
# Step 7: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
if [ -d "$VGC_DIR/.git" ]; then
    echo "[vgc-agent-kit] Repo already exists at $VGC_DIR — pulling latest..."
    git -C "$VGC_DIR" checkout main 2>/dev/null || true
    git -C "$VGC_DIR" pull --ff-only origin main || {
        echo "[vgc-agent-kit] WARNING: Pull failed. Continuing with current version."
    }
elif [ -d "$VGC_DIR" ]; then
    echo "[vgc-agent-kit] Directory $VGC_DIR exists but is not a git repo."
    read -rp "Overwrite? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "[vgc-agent-kit] Aborted."
        exit 0
    fi
    rm -rf "$VGC_DIR"
    echo "[vgc-agent-kit] Cloning repository..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-kit.git" "$VGC_DIR"
    echo "[vgc-agent-kit] Cloned successfully."
else
    echo "[vgc-agent-kit] Cloning repository..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-kit.git" "$VGC_DIR"
    echo "[vgc-agent-kit] Cloned successfully."
fi

# ──────────────────────────────────────────
# Step 8: Clone/update workspace
# ──────────────────────────────────────────
if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "[vgc-agent-kit] Workspace already exists — pulling latest..."
    git -C "$WORKSPACE_DIR" pull --ff-only 2>/dev/null || echo "[vgc-agent-kit] Workspace pull skipped."
elif [ -d "$WORKSPACE_DIR" ]; then
    echo "[vgc-agent-kit] Directory $WORKSPACE_DIR exists but is not a git repo."
    read -rp "Overwrite? (y/N): " overwrite_ws
    if [[ "$overwrite_ws" != "y" && "$overwrite_ws" != "Y" ]]; then
        echo "[vgc-agent-kit] Skipping workspace setup."
    else
        rm -rf "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Cloning workspace..."
        git clone --quiet "https://github.com/vgcorpvn/vgc-agent-workspace.git" "$WORKSPACE_DIR"
        echo "[vgc-agent-kit] Workspace cloned successfully."
    fi
else
    echo "[vgc-agent-kit] Cloning workspace..."
    git clone --quiet "https://github.com/vgcorpvn/vgc-agent-workspace.git" "$WORKSPACE_DIR"
    echo "[vgc-agent-kit] Workspace cloned successfully."
fi

# ──────────────────────────────────────────
# Step 9: Scout token (optional) — source repos (read-only)
# ──────────────────────────────────────────
# Separate token for source repos (least privilege).
# Stored in ~/.vgc/config/scout-token (outside git repo)
# Skills read this file and use: GH_TOKEN=$(cat ~/.vgc/config/scout-token) gh api ...

SKIP_SCOUT=false

# Check if current token already has repo access
if command -v gh &>/dev/null && gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
    echo "[vgc-agent-kit] Token already has source repo access — no separate token needed."
    # Save current token as scout token so skills have a consistent path
    mkdir -p "$CONFIG_DIR"
    gh auth token -h github.com 2>/dev/null > "$SCOUT_TOKEN_FILE" || true
    chmod 600 "$SCOUT_TOKEN_FILE" 2>/dev/null || true
    SKIP_SCOUT=true
fi

# Check if existing scout token still works
if [ "$SKIP_SCOUT" = false ] && [ -f "$SCOUT_TOKEN_FILE" ]; then
    EXISTING_SCOUT_TOKEN=$(cat "$SCOUT_TOKEN_FILE" 2>/dev/null || echo "")
    if [ -n "$EXISTING_SCOUT_TOKEN" ]; then
        if GH_TOKEN="$EXISTING_SCOUT_TOKEN" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            echo "[vgc-agent-kit] Existing scout token is valid — reusing."
            SKIP_SCOUT=true
        else
            echo "[vgc-agent-kit] Repo scout token expired — need to re-enter."
        fi
    fi
fi

if [ "$SKIP_SCOUT" = false ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│  Repo scout token — for source repos (read-only)  │"
    echo "│                                                        │"
    echo "│  Scope: repo:read for vgcorpvn/mobile.vhandicap.com   │"
    echo "│  Used by skill /discover-repo (reads knowledge/index.json + DS + BD)   │"
    echo "│  Press Enter to skip if not needed                     │"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
    read -rsp "Enter scout token (Enter to skip): " SCOUT_PAT
    echo ""

    if [ -n "$SCOUT_PAT" ]; then
        # Verify scout token
        if GH_TOKEN="$SCOUT_PAT" gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' &>/dev/null; then
            mkdir -p "$CONFIG_DIR"
            echo "$SCOUT_PAT" > "$SCOUT_TOKEN_FILE"
            chmod 600 "$SCOUT_TOKEN_FILE"
            echo "[vgc-agent-kit] Repo scout token OK."
            echo ""
            echo "[vgc-agent-kit] Verifying scout token..."
            verify_repo "vgcorpvn/mobile.vhandicap.com" "Source repo" false "$SCOUT_PAT"
        else
            echo "[vgc-agent-kit] WARNING: Repo scout token is invalid."
            echo "[vgc-agent-kit] Skill /discover-repo will not work."
        fi
    else
        echo "[vgc-agent-kit] Skipped scout token. Skill /discover-repo will not work."
    fi
fi

echo ""

# ──────────────────────────────────────────
# Step 10: Symlink skills to ~/.claude/skills/
# ──────────────────────────────────────────
mkdir -p "$CLAUDE_SKILLS_DIR"

# Remove stale symlinks (skills deleted/renamed in repo)
for link in "$CLAUDE_SKILLS_DIR"/vgc-agent-kit-*; do
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
    rm -f "$CLAUDE_SKILLS_DIR/$skill_name"
    ln -s "$skill_dir" "$CLAUDE_SKILLS_DIR/$skill_name"
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
    } >> "$SHELL_RC" || echo "[vgc-agent-kit] WARNING: Could not write alias to $SHELL_RC"
    echo "[vgc-agent-kit] Alias added to $SHELL_RC"
fi

eval "$ALIAS_LINE" 2>/dev/null || true

# ──────────────────────────────────────────
# Done
# ──────────────────────────────────────────
echo ""
echo "======================================"
echo "  Setup complete!"
echo "======================================"
echo ""
echo "  Skills location: $CLAUDE_SKILLS_DIR"
echo "  Repo location:   $VGC_DIR"
echo "  Workspace:       $WORKSPACE_DIR"
echo "  Auth:"
echo "    gh CLI:        authenticated (kit + workspace)"
if [ -f "$SCOUT_TOKEN_FILE" ]; then
echo "    Repo scout token:  $SCOUT_TOKEN_FILE"
else
echo "    Repo scout token:  not configured (skill /discover-repo disabled)"
fi
echo "  Auto-sync:       pulls automatically when a skill is used"
echo "  Manual update:   vgc-agent-kit-update-claude"
echo ""
echo "  Restart Claude Code to load skills."
echo "  Type / to see the list of available skills."
echo ""
