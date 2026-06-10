$ErrorActionPreference = "Stop"

$VGC_DIR = "$env:USERPROFILE\.vgc-agent-kit"
$CLAUDE_DIR = "$env:USERPROFILE\.claude"
$PLUGINS_FILE = "$CLAUDE_DIR\plugins\installed_plugins.json"
$SETTINGS_FILE = "$CLAUDE_DIR\settings.json"
$PLUGIN_KEY = "vgc-agent-kit@local"

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
if (-not (Test-Path $CLAUDE_DIR)) {
    Write-Host "[vgc-agent-kit] ERROR: Thu muc $CLAUDE_DIR khong ton tai."
    Write-Host "[vgc-agent-kit] Vui long cai Claude Code truoc: https://claude.ai/download"
    exit 1
}

Write-Host "[vgc-agent-kit] Claude Code OK."

# Step 3: Check existing installation
if (Test-Path $VGC_DIR) {
    Write-Host "[vgc-agent-kit] Da cai dat truoc do tai $VGC_DIR"
    $overwrite = Read-Host "Ghi de? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "[vgc-agent-kit] Huy bo."
        exit 0
    }
    Remove-Item -Recurse -Force $VGC_DIR
}

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

# Step 6: Store credentials for future pulls
& git -C $VGC_DIR config credential.helper store
$credentialInput = "protocol=https`nhost=github.com`nusername=${TOKEN_PLAIN}`npassword=${TOKEN_PLAIN}`n"
$credentialInput | & git -C $VGC_DIR credential approve 2>$null

# Step 7: Register as Claude Code plugin
$pluginsDir = "$CLAUDE_DIR\plugins"
if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
}

# 7a: Update installed_plugins.json
if (-not (Test-Path $PLUGINS_FILE)) {
    '{"version":2,"plugins":{}}' | Set-Content -Path $PLUGINS_FILE -Encoding UTF8
}

$installDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

try {
    $pluginsData = Get-Content $PLUGINS_FILE -Raw | ConvertFrom-Json

    if (-not $pluginsData.plugins) {
        $pluginsData | Add-Member -NotePropertyName "plugins" -NotePropertyValue @{} -Force
    }

    $entry = @{
        scope = "user"
        installPath = $VGC_DIR
        version = "1.0.0"
        installedAt = $installDate
        lastUpdated = $installDate
    }

    if ($pluginsData.plugins.PSObject.Properties[$PLUGIN_KEY]) {
        $pluginsData.plugins.$PLUGIN_KEY = @($entry)
    } else {
        $pluginsData.plugins | Add-Member -NotePropertyName $PLUGIN_KEY -NotePropertyValue @($entry)
    }

    $pluginsData | ConvertTo-Json -Depth 10 | Set-Content -Path $PLUGINS_FILE -Encoding UTF8
    Write-Host "[vgc-agent-kit] Plugin dang ky vao installed_plugins.json."
} catch {
    Write-Host "[vgc-agent-kit] WARNING: Khong the dang ky plugin tu dong."
    Write-Host "[vgc-agent-kit] Chay Claude Code voi: claude --plugin-dir $VGC_DIR"
}

# 7b: Enable plugin in settings.json
if (-not (Test-Path $SETTINGS_FILE)) {
    '{}' | Set-Content -Path $SETTINGS_FILE -Encoding UTF8
}

try {
    $settingsData = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json

    if (-not $settingsData.enabledPlugins) {
        $settingsData | Add-Member -NotePropertyName "enabledPlugins" -NotePropertyValue @{} -Force
    }

    if ($settingsData.enabledPlugins.PSObject.Properties[$PLUGIN_KEY]) {
        $settingsData.enabledPlugins.$PLUGIN_KEY = $true
    } else {
        $settingsData.enabledPlugins | Add-Member -NotePropertyName $PLUGIN_KEY -NotePropertyValue $true
    }

    $settingsData | ConvertTo-Json -Depth 10 | Set-Content -Path $SETTINGS_FILE -Encoding UTF8
    Write-Host "[vgc-agent-kit] Plugin da bat trong settings.json."
} catch {
    Write-Host "[vgc-agent-kit] WARNING: Khong the bat plugin trong settings."
    Write-Host "[vgc-agent-kit] Bat thu cong trong Claude Code: /plugins"
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
Write-Host "  Plugin:        $PLUGIN_KEY"
Write-Host "  Repo location: $VGC_DIR"
Write-Host "  Auto-update:   Daily luc 9h sang"
Write-Host "  Manual update: vgc-agent-kit-update-claude"
Write-Host ""
Write-Host "  Khoi dong lai Claude Code de load skills."
Write-Host "  Go / de xem danh sach skills."
Write-Host ""
