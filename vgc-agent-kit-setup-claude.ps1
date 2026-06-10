$ErrorActionPreference = "Stop"

$VGC_DIR = "$env:USERPROFILE\.vgc-agent-kit"
$CLAUDE_SKILLS_DIR = "$env:USERPROFILE\.claude\skills"

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
        Write-Host "[vgc-agent-kit] Repo da ton tai tai $VGC_DIR — dung lai (skip clone)."
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
    # Step 4: Ask for token
    Write-Host ""
    Write-Host "Can GitHub Personal Access Token (PAT) voi quyen repo:read."
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

    # Step 5: Clone repo
    $REPO_URL = "https://${TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-kit.git"
    Write-Host "[vgc-agent-kit] Dang clone repository..."
    & git clone --quiet $REPO_URL $VGC_DIR 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[vgc-agent-kit] ERROR: Clone that bai. Kiem tra lai token va quyen truy cap repo."
        exit 1
    }

    Write-Host "[vgc-agent-kit] Clone thanh cong."

    # Step 6: Store credentials
    & git -C $VGC_DIR config credential.helper store
    $credentialInput = "protocol=https`nhost=github.com`nusername=${TOKEN_PLAIN}`npassword=${TOKEN_PLAIN}`n"
    $credentialInput | & git -C $VGC_DIR credential approve 2>$null
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

# Step 8: Install scheduled task (best-effort)
$taskName = "VGCAgentKitUpdateClaude"

try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $action = New-ScheduledTaskAction -Execute "git" -Argument "-C `"$VGC_DIR`" pull --ff-only"
    $trigger = New-ScheduledTaskTrigger -Daily -At 9am
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "VGC Agent Kit daily update (Claude)" | Out-Null

    Write-Host "[vgc-agent-kit] Scheduled task cai dat: chay moi ngay luc 9h sang."
} catch {
    Write-Host "[vgc-agent-kit] WARNING: Khong the tao scheduled task (can quyen Admin)."
    Write-Host "[vgc-agent-kit] Ban co the chay thu cong: vgc-agent-kit-update-claude"
}

# Step 9: Add alias to PowerShell profile
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
Write-Host "  Auto-update:   Daily luc 9h sang"
Write-Host "  Manual update: vgc-agent-kit-update-claude"
Write-Host ""
Write-Host "  Khoi dong lai Claude Code de load skills."
Write-Host "  Go / de xem danh sach skills."
Write-Host ""
