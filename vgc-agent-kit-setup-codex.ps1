$ErrorActionPreference = "Stop"

$VGC_DIR = "$env:USERPROFILE\.vgc-agent-kit"
$SKILLS_DIR = "$env:USERPROFILE\.agents\skills"
$WORKSPACE_DIR = "$env:USERPROFILE\.vgc-agent-workspace"

Write-Host "======================================"
Write-Host "  VGC Agent Kit - Setup (Codex CLI)"
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
    Write-Host ""
    Write-Host "Sau khi cai xong, chay lai script nay."
    exit 1
}

# Step 2: Check existing installation — reuse if already cloned (e.g. by Claude setup)
$SKIP_CLONE = $false
if (Test-Path $VGC_DIR) {
    if (Test-Path "$VGC_DIR\.git") {
        Write-Host "[vgc-agent-kit] Repo da ton tai tai $VGC_DIR — dung lai (skip clone)."
        # Sanitize: strip any token from remote URL (fix from earlier installs)
        $currentUrl = & git -C $VGC_DIR remote get-url origin 2>$null
        if ($currentUrl -match "@github\.com" -and $currentUrl -notmatch "^git@") {
            & git -C $VGC_DIR remote set-url origin "https://github.com/vgcorpvn/vgc-agent-kit.git"
            Write-Host "[vgc-agent-kit] Da xoa token khoi remote URL."
        }
        & git -C $VGC_DIR pull --ff-only 2>$null
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
    # Step 3: Ask for token
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

    # Step 4: Clone repo
    $REPO_URL = "https://${TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-kit.git"
    Write-Host "[vgc-agent-kit] Dang clone repository..."
    & git clone --quiet $REPO_URL $VGC_DIR 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[vgc-agent-kit] ERROR: Clone that bai. Kiem tra lai token va quyen truy cap repo."
        exit 1
    }

    Write-Host "[vgc-agent-kit] Clone thanh cong."

    # Step 5: Strip token from remote URL + store credentials for future pulls
    & git -C $VGC_DIR remote set-url origin "https://github.com/vgcorpvn/vgc-agent-kit.git"
    & git -C $VGC_DIR config credential.helper store
    $credentialInput = "protocol=https`nhost=github.com`nusername=${TOKEN_PLAIN}`npassword=${TOKEN_PLAIN}`n"
    $credentialInput | & git -C $VGC_DIR credential approve 2>$null
}

# Step 5b: Check/install gh CLI
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

# Step 5c: Clone workspace repo
$SKIP_WORKSPACE = $false
if (Test-Path $WORKSPACE_DIR) {
    if (Test-Path "$WORKSPACE_DIR\.git") {
        Write-Host "[vgc-agent-kit] Workspace repo da ton tai — dung lai."
        # Sanitize: strip any token from remote URL
        $wsUrl = & git -C $WORKSPACE_DIR remote get-url origin 2>$null
        if ($wsUrl -match "@github\.com" -and $wsUrl -notmatch "^git@") {
            & git -C $WORKSPACE_DIR remote set-url origin "https://github.com/vgcorpvn/vgc-agent-workspace.git"
            Write-Host "[vgc-agent-kit] Da xoa token khoi workspace remote URL."
        }
        & git -C $WORKSPACE_DIR pull --ff-only 2>$null
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
        $WS_URL = "https://${WS_TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-workspace.git"
        Write-Host "[vgc-agent-kit] Dang clone workspace..."
        & git clone --quiet $WS_URL $WORKSPACE_DIR 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[vgc-agent-kit] WARNING: Clone workspace that bai. Kiem tra token va quyen."
        } else {
            Write-Host "[vgc-agent-kit] Workspace clone thanh cong."

            # Strip token from remote URL + store credentials
            & git -C $WORKSPACE_DIR remote set-url origin "https://github.com/vgcorpvn/vgc-agent-workspace.git"
            & git -C $WORKSPACE_DIR config credential.helper store
            $wsCred = "protocol=https`nhost=github.com`nusername=${WS_TOKEN_PLAIN}`npassword=${WS_TOKEN_PLAIN}`n"
            $wsCred | & git -C $WORKSPACE_DIR credential approve 2>$null

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

# Step 5d: Store mobile repo token for gh api access (optional)
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

# Step 6: Symlink skills using Junction (no admin required)
# SymbolicLink requires Administrator or Developer Mode enabled
# Junction works for directories without elevation
if (-not (Test-Path $SKILLS_DIR)) {
    New-Item -ItemType Directory -Path $SKILLS_DIR -Force | Out-Null
}

Get-ChildItem -Path "$VGC_DIR\skills" -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillPath = $_.FullName
    $linkPath = Join-Path $SKILLS_DIR $skillName

    if (-not (Test-Path "$skillPath\SKILL.md")) { return }

    if (Test-Path $linkPath) { Remove-Item $linkPath -Force -Recurse }

    try {
        New-Item -ItemType Junction -Path $linkPath -Target $skillPath -Force | Out-Null
    } catch {
        # Fallback to SymbolicLink if Junction fails (shouldn't happen on NTFS)
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $skillPath -Force | Out-Null
    }
    Write-Host "[vgc-agent-kit] Linked skill: $skillName"
}

# Step 7: Add alias to PowerShell profile
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$aliasLine = "function vgc-agent-kit-update-codex { & `"$updateScript`" }"

if (-not (Select-String -Path $profilePath -Pattern "vgc-agent-kit-update-codex" -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $profilePath -Value ""
    Add-Content -Path $profilePath -Value "# VGC Agent Kit"
    Add-Content -Path $profilePath -Value $aliasLine
    Write-Host "[vgc-agent-kit] Alias added to PowerShell profile"
}

# Load alias in current session (equivalent to Mac's eval)
Invoke-Expression $aliasLine

Write-Host ""
Write-Host "======================================"
Write-Host "  Setup hoan tat!"
Write-Host "======================================"
Write-Host ""
Write-Host "  Skills location: $SKILLS_DIR"
Write-Host "  Repo location:   $VGC_DIR"
Write-Host "  Workspace:       $WORKSPACE_DIR"
Write-Host "  Auto-sync:       Pull tu dong moi khi dung skill"
Write-Host "  Manual update:   vgc-agent-kit-update-codex"
Write-Host ""
