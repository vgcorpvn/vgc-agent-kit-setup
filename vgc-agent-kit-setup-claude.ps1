$ErrorActionPreference = "Stop"

$VGC_ROOT = "$env:USERPROFILE\.vgc"
$VGC_DIR = "$VGC_ROOT\agent-kit"
$CLAUDE_SKILLS_DIR = "$env:USERPROFILE\.claude\skills"
$WORKSPACE_DIR = "$VGC_ROOT\agent-workspace"
$CONFIG_DIR = "$VGC_ROOT\config"
$SCOUT_TOKEN_FILE = "$CONFIG_DIR\scout-token"

$env:GIT_TERMINAL_PROMPT = "0"

if (-not (Test-Path $VGC_ROOT)) { New-Item -ItemType Directory -Path $VGC_ROOT -Force | Out-Null }

Write-Host "======================================"
Write-Host "  VGC Agent Kit - Setup (Claude Code)"
Write-Host "======================================"
Write-Host ""

# ──────────────────────────────────────────
# Step 1: Check git
# ──────────────────────────────────────────
try {
    $gitVersion = & git --version 2>$null
    if (-not $gitVersion) { throw "not found" }
    Write-Host "[vgc-agent-kit] Git OK: $gitVersion"
} catch {
    Write-Host "[vgc-agent-kit] Git is not installed."
    Write-Host "  https://git-scm.com/download/win"
    exit 1
}

# ──────────────────────────────────────────
# Step 2: Check Claude Code installed
# ──────────────────────────────────────────
if (-not (Test-Path "$env:USERPROFILE\.claude")) {
    Write-Host "[vgc-agent-kit] ERROR: ~/.claude directory not found."
    Write-Host "[vgc-agent-kit] Please install Claude Code first: https://claude.ai/download"
    exit 1
}

Write-Host "[vgc-agent-kit] Claude Code OK."

# ──────────────────────────────────────────
# Step 3: Check/install gh CLI
# ──────────────────────────────────────────
$ghInstalled = $false
try {
    $ghVersion = & gh --version 2>$null | Select-Object -First 1
    if ($ghVersion) {
        Write-Host "[vgc-agent-kit] gh CLI OK: $ghVersion"
        $ghInstalled = $true
    }
} catch {}

if (-not $ghInstalled) {
    Write-Host "[vgc-agent-kit] GitHub CLI (gh) not found. Installing..."
    try {
        & winget install GitHub.cli --accept-package-agreements --accept-source-agreements 2>$null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $ghInstalled = $true
        Write-Host "[vgc-agent-kit] gh CLI installed successfully."
    } catch {
        Write-Host "[vgc-agent-kit] WARNING: Failed to install gh. Install manually: https://cli.github.com/"
    }
}

# ──────────────────────────────────────────
# Step 4: Authenticate gh CLI — kit + workspace (read+write)
# ──────────────────────────────────────────
$NEED_MAIN_TOKEN = $true

if ($ghInstalled) {
    & gh auth status -h github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[vgc-agent-kit] gh CLI already authenticated."

        $reposOk = $true
        & gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $reposOk = $false }
        & gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $reposOk = $false }

        if ($reposOk) {
            Write-Host "[vgc-agent-kit] Token access OK — reusing."
            $NEED_MAIN_TOKEN = $false
        } else {
            Write-Host "[vgc-agent-kit] Token lacks required permissions — need a new token."
        }
    }
}

if ($NEED_MAIN_TOKEN) {
    Write-Host ""
    Write-Host "+---------------------------------------------------------+"
    Write-Host "|  Main token (GitHub PAT) — for kit + workspace             |"
    Write-Host "|                                                         |"
    Write-Host "|  Minimum scopes: repo, read:org                         |"
    Write-Host "|  Token must have access to:                             |"
    Write-Host "|    - vgcorpvn/vgc-agent-kit        (read+write)         |"
    Write-Host "|    - vgcorpvn/vgc-agent-workspace   (read+write)        |"
    Write-Host "|                                                         |"
    Write-Host "|  Create at: https://github.com/settings/tokens          |"
    Write-Host "+---------------------------------------------------------+"
    Write-Host ""

    $secureToken = Read-Host "Enter main token (GitHub PAT)" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    $MAIN_TOKEN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    if ([string]::IsNullOrWhiteSpace($MAIN_TOKEN)) {
        Write-Host "[vgc-agent-kit] ERROR: Token cannot be empty."
        exit 1
    }

    if ($ghInstalled) {
        Write-Host "[vgc-agent-kit] Authenticating gh CLI..."
        $MAIN_TOKEN | & gh auth login -h github.com --with-token 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[vgc-agent-kit] ERROR: gh auth login failed."
            exit 1
        }
        Write-Host "[vgc-agent-kit] gh auth OK."
    }
}

# ──────────────────────────────────────────
# Step 5: Setup gh as git credential helper
# ──────────────────────────────────────────
if ($ghInstalled) {
    Write-Host "[vgc-agent-kit] Syncing credentials: gh -> git..."
    & gh auth setup-git -h github.com 2>$null
    Write-Host "[vgc-agent-kit] git credential helper = gh CLI."
}

# ──────────────────────────────────────────
# Step 6: Verify repo access
# ──────────────────────────────────────────
Write-Host ""
Write-Host "[vgc-agent-kit] Verifying repo access..."

$verifyOk = $true
if ($ghInstalled) {
    $r1 = & gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $r1) { Write-Host "  OK Agent Kit" } else { Write-Host "  FAIL Agent Kit"; $verifyOk = $false }
    $r2 = & gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $r2) { Write-Host "  OK Workspace" } else { Write-Host "  FAIL Workspace"; $verifyOk = $false }
}

if (-not $verifyOk) {
    Write-Host "[vgc-agent-kit] ERROR: Token lacks required permissions."
    exit 1
}

Write-Host ""

# ──────────────────────────────────────────
# Step 7: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
$REPO_URL = "https://github.com/vgcorpvn/vgc-agent-kit.git"

if (Test-Path "$VGC_DIR\.git") {
    Write-Host "[vgc-agent-kit] Repo already exists — pulling latest..."
    & git -C $VGC_DIR checkout main 2>$null
    & git -C $VGC_DIR pull --ff-only origin main 2>$null
} elseif (Test-Path $VGC_DIR) {
    $overwrite = Read-Host "Directory $VGC_DIR exists but is not a git repo. Overwrite? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") { exit 0 }
    Remove-Item -Recurse -Force $VGC_DIR
    & git clone --quiet $REPO_URL $VGC_DIR
    Write-Host "[vgc-agent-kit] Cloned successfully."
} else {
    & git clone --quiet $REPO_URL $VGC_DIR
    Write-Host "[vgc-agent-kit] Cloned successfully."
}

# ──────────────────────────────────────────
# Step 8: Clone/update workspace
# ──────────────────────────────────────────
$WORKSPACE_URL = "https://github.com/vgcorpvn/vgc-agent-workspace.git"

if (Test-Path "$WORKSPACE_DIR\.git") {
    Write-Host "[vgc-agent-kit] Workspace already exists — pulling latest..."
    & git -C $WORKSPACE_DIR pull --ff-only 2>$null
} elseif (Test-Path $WORKSPACE_DIR) {
    $overwriteWs = Read-Host "Workspace exists but is not a git repo. Overwrite? (y/N)"
    if ($overwriteWs -ne "y" -and $overwriteWs -ne "Y") {
        Write-Host "[vgc-agent-kit] Skipping workspace setup."
    } else {
        Remove-Item -Recurse -Force $WORKSPACE_DIR
        & git clone --quiet $WORKSPACE_URL $WORKSPACE_DIR
        Write-Host "[vgc-agent-kit] Workspace cloned successfully."
    }
} else {
    & git clone --quiet $WORKSPACE_URL $WORKSPACE_DIR
    Write-Host "[vgc-agent-kit] Workspace cloned successfully."
}

# ──────────────────────────────────────────
# Step 9: Scout token (optional) — source repos (read-only)
# ──────────────────────────────────────────
$skipScout = $false

if ($ghInstalled) {
    $scoutCheck = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $scoutCheck) {
        Write-Host "[vgc-agent-kit] Token already has source repo access — no separate token needed."
        if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
        & gh auth token -h github.com 2>$null | Out-File -FilePath $SCOUT_TOKEN_FILE -Encoding ascii -NoNewline
        $skipScout = $true
    }
}

if (-not $skipScout -and (Test-Path $SCOUT_TOKEN_FILE)) {
    $existing = Get-Content $SCOUT_TOKEN_FILE -Raw -ErrorAction SilentlyContinue
    if ($existing) {
        $env:GH_TOKEN = $existing.Trim()
        $check = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -and $check) {
            Write-Host "[vgc-agent-kit] Existing scout token is valid — reusing."
            $skipScout = $true
        }
    }
}

if (-not $skipScout) {
    Write-Host ""
    Write-Host "+---------------------------------------------------------+"
    Write-Host "|  Scout token — for source repos (read-only, optional)     |"
    Write-Host "|                                                         |"
    Write-Host "|  Scope: repo:read for vgcorpvn/mobile.vhandicap.com    |"
    Write-Host "|  Press Enter to skip if not needed                      |"
    Write-Host "+---------------------------------------------------------+"
    Write-Host ""

    $secureTokenB = Read-Host "Enter scout token (Enter to skip)" -AsSecureString
    $BSTR_B = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureTokenB)
    $SCOUT_PAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_B)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_B)

    if (-not [string]::IsNullOrWhiteSpace($SCOUT_PAT)) {
        $env:GH_TOKEN = $SCOUT_PAT
        $check = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -eq 0 -and $check) {
            if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
            $SCOUT_PAT | Out-File -FilePath $SCOUT_TOKEN_FILE -Encoding ascii -NoNewline
            Write-Host "[vgc-agent-kit] Scout token OK."
        } else {
            Write-Host "[vgc-agent-kit] WARNING: Scout token is invalid."
        }
    } else {
        Write-Host "[vgc-agent-kit] Skipped scout token."
    }
}

Write-Host ""

# ──────────────────────────────────────────
# Step 10: Symlink skills
# ──────────────────────────────────────────
if (-not (Test-Path $CLAUDE_SKILLS_DIR)) {
    New-Item -ItemType Directory -Path $CLAUDE_SKILLS_DIR -Force | Out-Null
}

# Remove stale symlinks (skills deleted/renamed in repo)
Get-ChildItem -Path $CLAUDE_SKILLS_DIR -Directory -Filter "vgc-agent-kit-*" -ErrorAction SilentlyContinue | Where-Object {
    $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
} | ForEach-Object {
    $target = (Get-Item $_.FullName).Target
    if ($target -like "$VGC_DIR\skills\*" -and -not (Test-Path $target)) {
        Remove-Item $_.FullName -Force
        Write-Host "[vgc-agent-kit] Removed stale skill: $($_.Name)"
    }
}

Get-ChildItem -Path "$VGC_DIR\skills" -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillPath = $_.FullName
    $linkPath = Join-Path $CLAUDE_SKILLS_DIR $skillName

    if (-not (Test-Path "$skillPath\SKILL.md")) { return }
    if (Test-Path $linkPath) { Remove-Item $linkPath -Force -Recurse }

    try {
        New-Item -ItemType Junction -Path $linkPath -Target $skillPath -Force | Out-Null
    } catch {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $skillPath -Force | Out-Null
    }
    Write-Host "[vgc-agent-kit] Linked skill: $skillName"
}

# ──────────────────────────────────────────
# Step 11: Add alias
# ──────────────────────────────────────────
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$aliasLine = "function vgc-agent-kit-update-claude { & git -C `"$VGC_DIR`" pull --ff-only }"

if (-not (Select-String -Path $profilePath -Pattern "vgc-agent-kit-update-claude" -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $profilePath -Value ""
    Add-Content -Path $profilePath -Value "# VGC Agent Kit (Claude Code)"
    Add-Content -Path $profilePath -Value $aliasLine
    Write-Host "[vgc-agent-kit] Alias added to PowerShell profile"
}

Invoke-Expression $aliasLine

Write-Host ""
Write-Host "======================================"
Write-Host "  Setup complete!"
Write-Host "======================================"
Write-Host ""
Write-Host "  Skills location: $CLAUDE_SKILLS_DIR"
Write-Host "  Repo location:   $VGC_DIR"
Write-Host "  Workspace:       $WORKSPACE_DIR"
Write-Host "  Auth:"
Write-Host "    gh CLI:        authenticated (kit + workspace)"
if (Test-Path $SCOUT_TOKEN_FILE) {
    Write-Host "    Scout token:  $SCOUT_TOKEN_FILE"
} else {
    Write-Host "    Scout token:  not configured"
}
Write-Host ""
Write-Host "  Restart Claude Code to load skills."
Write-Host ""
