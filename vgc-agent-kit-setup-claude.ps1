$ErrorActionPreference = "Stop"

$VGC_ROOT = "$env:USERPROFILE\.vgc"
$VGC_DIR = "$VGC_ROOT\agent-kit"
$CLAUDE_SKILLS_DIR = "$env:USERPROFILE\.claude\skills"
$WORKSPACE_DIR = "$VGC_ROOT\agent-workspace"
$CONFIG_DIR = "$VGC_ROOT\config"
$MOBILE_TOKEN_FILE = "$CONFIG_DIR\mobile-token"

$env:GIT_TERMINAL_PROMPT = "0"

# ──────────────────────────────────────────
# Migration: move old paths into ~/.vgc/
# ──────────────────────────────────────────
if (-not (Test-Path $VGC_ROOT)) { New-Item -ItemType Directory -Path $VGC_ROOT -Force | Out-Null }

if ((Test-Path "$env:USERPROFILE\.vgc-agent-kit") -and (-not (Test-Path $VGC_DIR))) {
    Move-Item "$env:USERPROFILE\.vgc-agent-kit" $VGC_DIR
    Write-Host "[vgc-agent-kit] Migrated ~/.vgc-agent-kit -> ~/.vgc/agent-kit"
}

if ((Test-Path "$env:USERPROFILE\.vgc-agent-workspace") -and (-not (Test-Path $WORKSPACE_DIR))) {
    Move-Item "$env:USERPROFILE\.vgc-agent-workspace" $WORKSPACE_DIR
    Write-Host "[vgc-agent-kit] Migrated ~/.vgc-agent-workspace -> ~/.vgc/agent-workspace"
}

if ((Test-Path "$env:USERPROFILE\.config\vgc-agent-kit") -and (-not (Test-Path $CONFIG_DIR))) {
    Move-Item "$env:USERPROFILE\.config\vgc-agent-kit" $CONFIG_DIR
    Write-Host "[vgc-agent-kit] Migrated ~/.config/vgc-agent-kit -> ~/.vgc/config"
}

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
    Write-Host "[vgc-agent-kit] Git chua duoc cai dat."
    Write-Host "  https://git-scm.com/download/win"
    exit 1
}

# ──────────────────────────────────────────
# Step 2: Check Claude Code installed
# ──────────────────────────────────────────
if (-not (Test-Path "$env:USERPROFILE\.claude")) {
    Write-Host "[vgc-agent-kit] ERROR: Thu muc ~/.claude khong ton tai."
    Write-Host "[vgc-agent-kit] Cai Claude Code truoc: https://claude.ai/download"
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
    Write-Host "[vgc-agent-kit] GitHub CLI (gh) chua cai. Dang cai..."
    try {
        & winget install GitHub.cli --accept-package-agreements --accept-source-agreements 2>$null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $ghInstalled = $true
        Write-Host "[vgc-agent-kit] gh CLI da cai thanh cong."
    } catch {
        Write-Host "[vgc-agent-kit] WARNING: Khong the cai gh. Cai thu cong: https://cli.github.com/"
    }
}

# ──────────────────────────────────────────
# Step 4: Token A — kit + workspace (read+write)
# ──────────────────────────────────────────
$NEED_TOKEN_A = $true

if ($ghInstalled) {
    & gh auth status -h github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[vgc-agent-kit] gh CLI da authenticated."

        $reposOk = $true
        & gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $reposOk = $false }
        & gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $reposOk = $false }

        if ($reposOk) {
            Write-Host "[vgc-agent-kit] Token A truy cap OK — dung lai."
            $NEED_TOKEN_A = $false
        } else {
            Write-Host "[vgc-agent-kit] Token A thieu quyen — can nhap token moi."
        }
    }
}

if ($NEED_TOKEN_A) {
    Write-Host ""
    Write-Host "+---------------------------------------------------------+"
    Write-Host "|  Token A — cho kit + workspace (read+write)              |"
    Write-Host "|                                                          |"
    Write-Host "|  Quyen toi thieu: repo, read:org                         |"
    Write-Host "|  Token can truy cap duoc:                                |"
    Write-Host "|    - vgcorpvn/vgc-agent-kit        (read+write)          |"
    Write-Host "|    - vgcorpvn/vgc-agent-workspace   (read+write)         |"
    Write-Host "|                                                          |"
    Write-Host "|  Tao tai: https://github.com/settings/tokens             |"
    Write-Host "+---------------------------------------------------------+"
    Write-Host ""

    $secureToken = Read-Host "Nhap Token A" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    $TOKEN_A = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    if ([string]::IsNullOrWhiteSpace($TOKEN_A)) {
        Write-Host "[vgc-agent-kit] ERROR: Token khong duoc de trong."
        exit 1
    }

    if ($ghInstalled) {
        Write-Host "[vgc-agent-kit] Dang xac thuc gh CLI voi Token A..."
        $TOKEN_A | & gh auth login -h github.com --with-token 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[vgc-agent-kit] ERROR: gh auth login that bai."
            exit 1
        }
        Write-Host "[vgc-agent-kit] gh auth OK."
    }
}

# ──────────────────────────────────────────
# Step 5: Setup gh as git credential helper
# ──────────────────────────────────────────
if ($ghInstalled) {
    Write-Host "[vgc-agent-kit] Dong bo credentials: gh -> git..."
    & gh auth setup-git -h github.com 2>$null
    Write-Host "[vgc-agent-kit] git credential helper = gh CLI."
}

# ──────────────────────────────────────────
# Step 6: Verify Token A
# ──────────────────────────────────────────
Write-Host ""
Write-Host "[vgc-agent-kit] Kiem tra Token A..."

$verifyOk = $true
if ($ghInstalled) {
    $r1 = & gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $r1) { Write-Host "  OK Agent Kit" } else { Write-Host "  FAIL Agent Kit"; $verifyOk = $false }
    $r2 = & gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $r2) { Write-Host "  OK Workspace" } else { Write-Host "  FAIL Workspace"; $verifyOk = $false }
}

if (-not $verifyOk) {
    Write-Host "[vgc-agent-kit] ERROR: Token A khong du quyen."
    exit 1
}

Write-Host ""

# ──────────────────────────────────────────
# Step 7: Clone/update vgc-agent-kit
# ──────────────────────────────────────────
$CLEAN_URL = "https://github.com/vgcorpvn/vgc-agent-kit.git"

if (Test-Path "$VGC_DIR\.git") {
    Write-Host "[vgc-agent-kit] Repo da ton tai — pulling latest..."
    $currentUrl = & git -C $VGC_DIR remote get-url origin 2>$null
    if ($currentUrl -ne $CLEAN_URL) {
        & git -C $VGC_DIR remote set-url origin $CLEAN_URL
    }
    & git -C $VGC_DIR checkout main 2>$null
    & git -C $VGC_DIR pull --ff-only origin main 2>$null
} elseif (Test-Path $VGC_DIR) {
    $overwrite = Read-Host "Thu muc $VGC_DIR ton tai nhung khong phai git repo. Ghi de? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") { exit 0 }
    Remove-Item -Recurse -Force $VGC_DIR
    & git clone --quiet $CLEAN_URL $VGC_DIR
    Write-Host "[vgc-agent-kit] Clone thanh cong."
} else {
    & git clone --quiet $CLEAN_URL $VGC_DIR
    Write-Host "[vgc-agent-kit] Clone thanh cong."
}

# ──────────────────────────────────────────
# Step 8: Clone/update workspace
# ──────────────────────────────────────────
$CLEAN_WS_URL = "https://github.com/vgcorpvn/vgc-agent-workspace.git"

if (Test-Path "$WORKSPACE_DIR\.git") {
    Write-Host "[vgc-agent-kit] Workspace da ton tai — pulling latest..."
    $wsUrl = & git -C $WORKSPACE_DIR remote get-url origin 2>$null
    if ($wsUrl -ne $CLEAN_WS_URL) {
        & git -C $WORKSPACE_DIR remote set-url origin $CLEAN_WS_URL
    }
    & git -C $WORKSPACE_DIR pull --ff-only 2>$null
} elseif (Test-Path $WORKSPACE_DIR) {
    $overwriteWs = Read-Host "Workspace ton tai nhung khong phai git repo. Ghi de? (y/N)"
    if ($overwriteWs -ne "y" -and $overwriteWs -ne "Y") {
        Write-Host "[vgc-agent-kit] Bo qua workspace."
    } else {
        Remove-Item -Recurse -Force $WORKSPACE_DIR
        & git clone --quiet $CLEAN_WS_URL $WORKSPACE_DIR
        Write-Host "[vgc-agent-kit] Workspace clone thanh cong."
    }
} else {
    & git clone --quiet $CLEAN_WS_URL $WORKSPACE_DIR
    Write-Host "[vgc-agent-kit] Workspace clone thanh cong."
}

# ──────────────────────────────────────────
# Step 9: Token B — mobile repo (read-only, optional)
# ──────────────────────────────────────────
$skipMobile = $false

if ($ghInstalled) {
    $mobileCheck = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $mobileCheck) {
        Write-Host "[vgc-agent-kit] Token A da truy cap duoc mobile repo — bo qua Token B."
        if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
        & gh auth token -h github.com 2>$null | Out-File -FilePath $MOBILE_TOKEN_FILE -Encoding ascii -NoNewline
        $skipMobile = $true
    }
}

if (-not $skipMobile -and (Test-Path $MOBILE_TOKEN_FILE)) {
    $existing = Get-Content $MOBILE_TOKEN_FILE -Raw -ErrorAction SilentlyContinue
    if ($existing) {
        $env:GH_TOKEN = $existing.Trim()
        $check = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -and $check) {
            Write-Host "[vgc-agent-kit] Token B (mobile) con hop le — dung lai."
            $skipMobile = $true
        }
    }
}

if (-not $skipMobile) {
    Write-Host ""
    Write-Host "+---------------------------------------------------------+"
    Write-Host "|  Token B — cho mobile repo (read-only, optional)         |"
    Write-Host "|                                                          |"
    Write-Host "|  Quyen: repo:read cho vgcorpvn/mobile.vhandicap.com     |"
    Write-Host "|  Enter de bo qua                                         |"
    Write-Host "+---------------------------------------------------------+"
    Write-Host ""

    $secureTokenB = Read-Host "Nhap Token B (Enter de bo qua)" -AsSecureString
    $BSTR_B = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureTokenB)
    $TOKEN_B = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_B)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_B)

    if (-not [string]::IsNullOrWhiteSpace($TOKEN_B)) {
        $env:GH_TOKEN = $TOKEN_B
        $check = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -eq 0 -and $check) {
            if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
            $TOKEN_B | Out-File -FilePath $MOBILE_TOKEN_FILE -Encoding ascii -NoNewline
            Write-Host "[vgc-agent-kit] Token B OK — mobile repo truy cap duoc."
        } else {
            Write-Host "[vgc-agent-kit] WARNING: Token B khong truy cap duoc mobile repo."
        }
    } else {
        Write-Host "[vgc-agent-kit] Bo qua Token B."
    }
}

Write-Host ""

# ──────────────────────────────────────────
# Step 10: Symlink skills
# ──────────────────────────────────────────
if (-not (Test-Path $CLAUDE_SKILLS_DIR)) {
    New-Item -ItemType Directory -Path $CLAUDE_SKILLS_DIR -Force | Out-Null
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
Write-Host "  Setup hoan tat!"
Write-Host "======================================"
Write-Host ""
Write-Host "  Skills location: $CLAUDE_SKILLS_DIR"
Write-Host "  Repo location:   $VGC_DIR"
Write-Host "  Workspace:       $WORKSPACE_DIR"
Write-Host "  Auth:"
Write-Host "    Token A: gh CLI (kit + workspace)"
if (Test-Path $MOBILE_TOKEN_FILE) {
    Write-Host "    Token B: $MOBILE_TOKEN_FILE (mobile, read-only)"
} else {
    Write-Host "    Token B: khong co"
}
Write-Host ""
Write-Host "  Khoi dong lai Claude Code de load skills."
Write-Host ""
