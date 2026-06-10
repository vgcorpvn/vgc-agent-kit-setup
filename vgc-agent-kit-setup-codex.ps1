$ErrorActionPreference = "Stop"

$VGC_DIR = "$env:USERPROFILE\.vgc-agent-kit"
$SKILLS_DIR = "$env:USERPROFILE\.agents\skills"

Write-Host "======================================"
Write-Host "  VGC Agent Kit - Setup (Codex CLI)"
Write-Host "======================================"
Write-Host ""

# Step 1: Check git
try {
    $gitVersion = git --version 2>$null
    Write-Host "[vgc-agent-kit] Git OK: $gitVersion"
} catch {
    Write-Host "[vgc-agent-kit] Git chua duoc cai dat."
    Write-Host "[vgc-agent-kit] Tai va cai Git for Windows tai:"
    Write-Host "  https://git-scm.com/download/win"
    Write-Host ""
    Write-Host "Sau khi cai xong, chay lai script nay."
    exit 1
}

# Step 2: Check existing installation
if (Test-Path $VGC_DIR) {
    Write-Host "[vgc-agent-kit] Da cai dat truoc do tai $VGC_DIR"
    $overwrite = Read-Host "Ghi de? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "[vgc-agent-kit] Huy bo."
        exit 0
    }
    Remove-Item -Recurse -Force $VGC_DIR
}

# Step 3: Ask for token
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

# Step 4: Clone repo
$REPO_URL = "https://${TOKEN_PLAIN}@github.com/vgcorpvn/vgc-agent-kit.git"
Write-Host "[vgc-agent-kit] Dang clone repository..."
git clone --quiet $REPO_URL $VGC_DIR 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[vgc-agent-kit] ERROR: Clone that bai. Kiem tra lai token va quyen truy cap repo."
    exit 1
}

Write-Host "[vgc-agent-kit] Clone thanh cong."

# Step 5: Store credentials
git -C $VGC_DIR config credential.helper manager

# Step 6: Symlink skills
if (-not (Test-Path $SKILLS_DIR)) {
    New-Item -ItemType Directory -Path $SKILLS_DIR -Force | Out-Null
}

Get-ChildItem -Path "$VGC_DIR\skills" -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillPath = $_.FullName
    $linkPath = Join-Path $SKILLS_DIR $skillName

    if (-not (Test-Path "$skillPath\SKILL.md")) { return }

    if (Test-Path $linkPath) { Remove-Item $linkPath -Force -Recurse }
    New-Item -ItemType SymbolicLink -Path $linkPath -Target $skillPath -Force | Out-Null
    Write-Host "[vgc-agent-kit] Linked skill: $skillName"
}

# Step 7: Install scheduled task
$taskName = "VGCAgentKitUpdate"
$updateScript = "$VGC_DIR\scripts\vgc-agent-kit-update-codex.ps1"

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$updateScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "VGC Agent Kit daily update" | Out-Null

Write-Host "[vgc-agent-kit] Scheduled task cai dat: chay moi ngay luc 9h sang."

# Step 8: Add alias to PowerShell profile
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$aliasLine = "function vgc-agent-kit-update-codex { & `"$updateScript`" }"

if (-not (Select-String -Path $profilePath -Pattern "vgc-agent-kit-update-codex" -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $profilePath -Value ""
    Add-Content -Path $profilePath -Value "# VGC Agent Kit"
    Add-Content -Path $profilePath -Value $aliasLine
    Write-Host "[vgc-agent-kit] Alias added to PowerShell profile"
}

Write-Host ""
Write-Host "======================================"
Write-Host "  Setup hoan tat!"
Write-Host "======================================"
Write-Host ""
Write-Host "  Skills location: $SKILLS_DIR"
Write-Host "  Repo location:   $VGC_DIR"
Write-Host "  Auto-update:     Daily luc 9h sang"
Write-Host "  Manual update:   vgc-agent-kit-update-codex"
Write-Host ""
Write-Host "  Mo PowerShell moi de su dung alias."
Write-Host ""
