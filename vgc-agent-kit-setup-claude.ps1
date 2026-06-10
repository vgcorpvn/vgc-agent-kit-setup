$ErrorActionPreference = "Stop"

$VGC_DIR = "$env:USERPROFILE\.vgc-agent-kit"
$CLAUDE_SKILLS_DIR = "$env:USERPROFILE\.claude\skills"
$WORKSPACE_DIR = "$env:USERPROFILE\.vgc-agent-workspace"

# Never prompt for credentials
$env:GIT_TERMINAL_PROMPT = "0"

Write-Host "======================================"
Write-Host "  VGC Agent Kit - Setup (Claude Code)"
Write-Host "======================================"
Write-Host ""

# Step 1: Check git
try {
    $gitVersion = & git --version 2>$null
    if (-not $gitVersion) { throw "not found" }
    Write-Host "[vgc-agent-kit] Git OK: $gitVersion"
} catch {
    Write-Host "[vgc-agent-kit] Git chua duoc cai dat."
    Write-Host "[vgc-agent-kit] Tai va cai Git for Windows tai:"
    Write-Host "  https://git-scm.com/download/win"
    exit 1
}

# Step 2: Check Claude Code installed
if (-not (Test-Path "$env:USERPROFILE\.claude")) {
    Write-Host "[vgc-agent-kit] ERROR: Thu muc ~/.claude khong ton tai."
    Write-Host "[vgc-agent-kit] Vui long cai Claude Code truoc: https://claude.ai/download"
    exit 1
}

Write-Host "[vgc-agent-kit] Claude Code OK."

# Step 3: Check existing installation — reuse if already cloned
$SKIP_CLONE = $false
if (Test-Path $VGC_DIR) {
    if (Test-Path "$VGC_DIR\.git") {
        # Check if remote URL has token — if not, token was stripped and we need to re-auth
        $currentUrl = & git -C $VGC_DIR remote get-url origin 2>$null
        if ($currentUrl -eq "https://github.com/vgcorpvn/vgc-agent-kit.git") {
            Write-Host "[vgc-agent-kit] URL khong co token — can nhap lai token de xac thuc."
            $tokenInput = Read-Host "Nhap GitHub token (PAT, repo:read+write)"
            if ([string]::IsNullOrWhiteSpace($tokenInput)) {
                Write-Host "[vgc-agent-kit] ERROR: Token khong duoc de trong."
                exit 1
            }
            & git -C $VGC_DIR remote set-url origin "https://${tokenInput}@github.com/vgcorpvn/vgc-agent-kit.git"
            Write-Host "[vgc-agent-kit] Token da duoc cap nhat vao remote URL."
            $GITHUB_TOKEN = $tokenInput
        }
        Write-Host "[vgc-agent-kit] Repo da ton tai tai $VGC_DIR — dung lai (skip clone)."
        & git -C $VGC_DIR pull --ff-only 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host "[vgc-agent-kit] Pull skipped (offline hoac token het han)." }
        $SKIP_CLONE = $true
    } else {
        Write-Host "[vgc-agent-kit] Thu muc $VGC_DIR ton tai nhung khong phai git repo."
        $overwrite = Read-Host "Ghi de? (y/N)"
        if ($overwrite -ne "y" -and $overwrite -ne "Y") {
            Write-Host "[vgc-agent-kit] Huy bo."
            exit 0
        }
        Remove-Item -Recurse -Force $VGC_DIR
    }
}

if (-not $SKIP_CLONE) {
    # Step 4: Ask for token
    Write-Host ""
    Write-Host "Can GitHub Personal Access Token (PAT) voi quyen repo:read+write."
    Write-Host "Token nay dung cho ca vgc-agent-kit va vgc-agent-workspace."
    Write-Host "Tao tai: https://github.com/settings/tokens"
    Write-Host ""
    $GITHUB_TOKEN = Read-Host "Nhap GitHub token" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($GITHUB_TOKEN)
    $TOKEN_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    if ([string]::IsNullOrWhiteSpace($TOKEN_PLAIN)) {
        Write-Host "[vgc-agent-kit] ERROR: Token khong duoc de trong."
        exit 1
    }

    # Step 5: Clone repo (token in URL for clone only)
    Write-Host "[vgc-agent-kit] Dang clone repository..."
    & git clone --quiet "https://${TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-kit.git" $VGC_DIR 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[vgc-agent-kit] ERROR: Clone that bai. Kiem tra lai token va quyen truy cap repo."
        exit 1
    }

    Write-Host "[vgc-agent-kit] Clone thanh cong."
}

# Step 6b: Check/install gh CLI
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

# Step 6c: Clone workspace repo
$SKIP_WORKSPACE = $false
if (Test-Path $WORKSPACE_DIR) {
    if (Test-Path "$WORKSPACE_DIR\.git") {
        # Check if remote URL has token — if not, re-prompt
        $wsUrl = & git -C $WORKSPACE_DIR remote get-url origin 2>$null
        if ($wsUrl -eq "https://github.com/vgcorpvn/vgc-agent-workspace.git") {
            if (-not [string]::IsNullOrWhiteSpace($TOKEN_PLAIN)) {
                $WS_TOKEN_PLAIN = $TOKEN_PLAIN
                Write-Host "[vgc-agent-kit] Workspace URL khong co token — cap nhat bang kit token."
            } else {
                Write-Host "[vgc-agent-kit] Workspace URL khong co token — can nhap lai."
                $wsTokenInput = Read-Host "Nhap GitHub token (PAT, repo:read+write)"
                $WS_TOKEN_PLAIN = $wsTokenInput
            }
            if (-not [string]::IsNullOrWhiteSpace($WS_TOKEN_PLAIN)) {
                & git -C $WORKSPACE_DIR remote set-url origin "https://${WS_TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-workspace.git"
            }
        }
        Write-Host "[vgc-agent-kit] Workspace repo da ton tai — dung lai."
        & git -C $WORKSPACE_DIR pull --ff-only 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host "[vgc-agent-kit] Workspace pull skipped." }
        $SKIP_WORKSPACE = $true
    } else {
        Write-Host "[vgc-agent-kit] Thu muc $WORKSPACE_DIR ton tai nhung khong phai git repo."
        $overwriteWs = Read-Host "Ghi de? (y/N)"
        if ($overwriteWs -ne "y" -and $overwriteWs -ne "Y") {
            Write-Host "[vgc-agent-kit] Bo qua workspace setup."
            $SKIP_WORKSPACE = $true
        } else {
            Remove-Item -Recurse -Force $WORKSPACE_DIR
        }
    }
}

if (-not $SKIP_WORKSPACE) {
    # Reuse Token A for workspace (same token, read+write)
    if (-not [string]::IsNullOrWhiteSpace($TOKEN_PLAIN)) {
        $WS_TOKEN_PLAIN = $TOKEN_PLAIN
        Write-Host "[vgc-agent-kit] Dung cung token cho workspace (read+write)."
    } else {
        Write-Host ""
        Write-Host "Can GitHub token (PAT) voi quyen repo:read+write cho workspace."
        $WS_TOKEN = Read-Host "Nhap GitHub token" -AsSecureString
        $BSTR_WS = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($WS_TOKEN)
        $WS_TOKEN_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_WS)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_WS)
    }

    if ([string]::IsNullOrWhiteSpace($WS_TOKEN_PLAIN)) {
        Write-Host "[vgc-agent-kit] WARNING: Token workspace trong. Bo qua workspace setup."
    } else {
        Write-Host "[vgc-agent-kit] Dang clone workspace..."
        & git clone --quiet "https://${WS_TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-workspace.git" $WORKSPACE_DIR 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[vgc-agent-kit] WARNING: Clone workspace that bai. Kiem tra token va quyen."
        } else {
            Write-Host "[vgc-agent-kit] Workspace clone thanh cong."

            # Auth gh CLI
            if ($ghInstalled) {
                try {
                    $WS_TOKEN_PLAIN | & gh auth login --with-token 2>$null
                    Write-Host "[vgc-agent-kit] gh CLI da auth."
                } catch {
                    Write-Host "[vgc-agent-kit] WARNING: gh auth login that bai."
                }
            }
        }
    }
}

# Step 6d: Store mobile repo token for gh api access (optional)
$SKIP_MOBILE = $false
if ($ghInstalled) {
    try {
        $mobileCheck = & gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' 2>$null
        if ($mobileCheck -eq "mobile.vhandicap.com") {
            Write-Host "[vgc-agent-kit] Mobile repo da truy cap duoc — skip token."
            $SKIP_MOBILE = $true
        }
    } catch {}
}

if (-not $SKIP_MOBILE) {
    Write-Host ""
    Write-Host "Can GitHub Token thu 2 (PAT) voi quyen repo:read cho mobile repo."
    Write-Host "Token nay dung de agent doc screen-index.json va source code."
    Write-Host "(Bo qua neu khong can discover-screen skill)"
    Write-Host ""
    $MOBILE_TOKEN = Read-Host "Nhap GitHub token (mobile, Enter de bo qua)" -AsSecureString
    $BSTR_M = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($MOBILE_TOKEN)
    $MOBILE_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_M)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_M)

    if (-not [string]::IsNullOrWhiteSpace($MOBILE_PLAIN)) {
        & git config --global credential.helper store
        $mobileCred = "protocol=https`nhost=github.com`nusername=${MOBILE_PLAIN}`npassword=${MOBILE_PLAIN}`n"
        $mobileCred | & git credential approve 2>$null
        Write-Host "[vgc-agent-kit] Mobile repo token da luu."
    }
}

# Step 7: Symlink skills to ~/.claude/skills/ (Junction, no admin needed)
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

# Step 8: Add alias to PowerShell profile
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
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
Write-Host "  Repo location: $VGC_DIR"
Write-Host "  Workspace:     $WORKSPACE_DIR"
Write-Host "  Auto-sync:     Pull tu dong moi khi dung skill"
Write-Host "  Manual update: vgc-agent-kit-update-claude"
Write-Host ""
Write-Host "  Khoi dong lai Claude Code de load skills."
Write-Host "  Go / de xem danh sach skills."
Write-Host ""
