$ErrorActionPreference = "Stop"
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$VGC_ROOT = "$env:USERPROFILE\.vgc"
$VGC_DIR = "$VGC_ROOT\agent-kit"
$CLAUDE_SKILLS_DIR = "$env:USERPROFILE\.claude\skills"
$WORKSPACE_DIR = "$VGC_ROOT\agent-workspace"
$CONFIG_DIR = "$VGC_ROOT\config"
$SCOUT_TOKEN_FILE = "$CONFIG_DIR\scout-token"

$env:GIT_TERMINAL_PROMPT = "0"

if (-not (Test-Path $VGC_ROOT)) { New-Item -ItemType Directory -Path $VGC_ROOT -Force | Out-Null }

function Refresh-ProcessPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $extraPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin",
        "${env:ProgramFiles(x86)}\Git\cmd",
        "$env:ProgramFiles\GitHub CLI",
        "$env:LOCALAPPDATA\Programs\Git\cmd",
        "$env:LOCALAPPDATA\Programs\GitHub CLI"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $env:Path = (@($machinePath, $userPath) + $extraPaths) -join ";"
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    Refresh-ProcessPath
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$ManualUrl
    )

    if (-not (Test-CommandAvailable "winget")) {
        Write-Host "[vgc-agent-kit] ERROR: winget is not available. Install $Label manually: $ManualUrl"
        return $false
    }

    Write-Host "[vgc-agent-kit] Installing $Label via winget..."
    & winget install --id $PackageId -e --accept-package-agreements --accept-source-agreements
    Refresh-ProcessPath

    if (Test-CommandAvailable $CommandName) {
        Write-Host "[vgc-agent-kit] $Label installed successfully."
        return $true
    }

    Write-Host "[vgc-agent-kit] ERROR: $Label install finished, but '$CommandName' is still not available in this shell."
    Write-Host "[vgc-agent-kit] Close and reopen PowerShell, then re-run this script. Manual install: $ManualUrl"
    return $false
}

function Read-SecretText {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $secureValue = Read-Host $Prompt -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Invoke-NativeQuiet {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $oldErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = [bool](Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($nativePreferenceExists) {
        $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        & $Command *> $null
        return $LASTEXITCODE
    } catch {
        return 1
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }
}

function Invoke-NativeOutput {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $oldErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = [bool](Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($nativePreferenceExists) {
        $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & $Command 2>$null
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            Output = $null
        }
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }
}

function Invoke-RequiredNative {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = [bool](Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($nativePreferenceExists) {
        $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        & $Command
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }

    if ($exitCode -ne 0) {
        Write-Host "[vgc-agent-kit] ERROR: $Description failed (exit code $exitCode)."
        exit 1
    }
}

function Remove-PathSafe {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        if ($item.PSIsContainer) {
            [System.IO.Directory]::Delete($item.FullName)
        } else {
            Remove-Item -LiteralPath $item.FullName -Force
        }
        return
    }

    Remove-Item -LiteralPath $item.FullName -Force -Recurse
}

function Clear-GhAuthEnvironment {
    $hadTokenEnv = $false
    if (Test-Path Env:\GH_TOKEN) {
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        $hadTokenEnv = $true
    }
    if (Test-Path Env:\GITHUB_TOKEN) {
        Remove-Item Env:\GITHUB_TOKEN -ErrorAction SilentlyContinue
        $hadTokenEnv = $true
    }
    if ($hadTokenEnv) {
        Write-Host "[vgc-agent-kit] Cleared GH_TOKEN/GITHUB_TOKEN for gh CLI login in this session."
    }
}

function Invoke-GhLoginWithToken {
    param([Parameter(Mandatory = $true)][string]$Token)

    Clear-GhAuthEnvironment
    $logoutExitCode = Invoke-NativeQuiet { gh auth logout -h github.com -y }
    if ($logoutExitCode -ne 0) {
        Write-Host "[vgc-agent-kit] gh auth logout skipped or failed; continuing with fresh token login."
    }

    $tokenFile = [System.IO.Path]::GetTempFileName()
    $oldErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = [bool](Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($nativePreferenceExists) {
        $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tokenFile, ($Token.Trim() + [Environment]::NewLine), $utf8NoBom)

        $ErrorActionPreference = "Continue"
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $loginCommand = "gh auth login -h github.com --with-token < `"$tokenFile`""
        & cmd.exe /d /c $loginCommand *> $null
        $loginExitCode = $LASTEXITCODE
    } catch {
        $loginExitCode = 1
    } finally {
        Remove-Item $tokenFile -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $oldErrorActionPreference
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }

    if ($loginExitCode -ne 0) {
        return $false
    }

    if ((Invoke-NativeQuiet { gh auth status -h github.com }) -ne 0) {
        return $false
    }

    if ((Invoke-NativeQuiet { gh auth token -h github.com }) -ne 0) {
        return $false
    }

    return $true
}

Write-Host "======================================"
Write-Host "  VGC Agent Kit - Setup (Claude Code)"
Write-Host "======================================"
Write-Host ""

# ──────────────────────────────────────────
# Step 1: Check git
# ──────────────────────────────────────────
if (-not (Test-CommandAvailable "git")) {
    Write-Host "[vgc-agent-kit] Git is not installed."
    if (-not (Install-WingetPackage -PackageId "Git.Git" -Label "Git" -CommandName "git" -ManualUrl "https://git-scm.com/download/win")) {
        exit 1
    }
}

$gitVersion = & git --version
Write-Host "[vgc-agent-kit] Git OK: $gitVersion"

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

if (-not (Test-CommandAvailable "gh")) {
    Write-Host "[vgc-agent-kit] GitHub CLI (gh) not found. Installing..."
    if (-not (Install-WingetPackage -PackageId "GitHub.cli" -Label "GitHub CLI (gh)" -CommandName "gh" -ManualUrl "https://cli.github.com/")) {
        exit 1
    }
}

$ghVersion = & gh --version | Select-Object -First 1
Write-Host "[vgc-agent-kit] gh CLI OK: $ghVersion"
$ghInstalled = $true

# ──────────────────────────────────────────
# Step 4: Authenticate gh CLI — kit + workspace (read+write)
# ──────────────────────────────────────────
$NEED_MAIN_TOKEN = $true

if ($ghInstalled) {
    Clear-GhAuthEnvironment
    if ((Invoke-NativeQuiet { gh auth status -h github.com }) -eq 0) {
        Write-Host ""
        Write-Host "[vgc-agent-kit] gh CLI already authenticated."

        $reposOk = $true
        if ((Invoke-NativeQuiet { gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' }) -ne 0) { $reposOk = $false }
        if ((Invoke-NativeQuiet { gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' }) -ne 0) { $reposOk = $false }

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

    $MAIN_TOKEN = Read-SecretText "Enter main token (GitHub PAT)"

    if ([string]::IsNullOrWhiteSpace($MAIN_TOKEN)) {
        Write-Host "[vgc-agent-kit] ERROR: Token cannot be empty."
        exit 1
    }

    if ($MAIN_TOKEN -notmatch "^(ghp_|github_pat_)") {
        Write-Host "[vgc-agent-kit] WARNING: Token does not start with ghp_ or github_pat_."
    }

    if ($ghInstalled) {
        Write-Host "[vgc-agent-kit] Authenticating gh CLI..."
        if (-not (Invoke-GhLoginWithToken $MAIN_TOKEN)) {
            Write-Host "[vgc-agent-kit] ERROR: gh auth login failed. Token may be invalid, expired, or missing required scopes."
            Write-Host "[vgc-agent-kit] The setup script could not make 'gh auth status' pass after login."
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
    Invoke-NativeQuiet { gh auth setup-git -h github.com } | Out-Null
    Write-Host "[vgc-agent-kit] git credential helper = gh CLI."
}

# ──────────────────────────────────────────
# Step 6: Verify repo access
# ──────────────────────────────────────────
Write-Host ""
Write-Host "[vgc-agent-kit] Verifying repo access..."

$verifyOk = $true
if ($ghInstalled) {
    $r1 = Invoke-NativeOutput { gh api repos/vgcorpvn/vgc-agent-kit --jq '.name' }
    if ($r1.ExitCode -eq 0 -and $r1.Output) { Write-Host "  OK Agent Kit" } else { Write-Host "  FAIL Agent Kit"; $verifyOk = $false }
    $r2 = Invoke-NativeOutput { gh api repos/vgcorpvn/vgc-agent-workspace --jq '.name' }
    if ($r2.ExitCode -eq 0 -and $r2.Output) { Write-Host "  OK Workspace" } else { Write-Host "  FAIL Workspace"; $verifyOk = $false }
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
    Invoke-RequiredNative "Checkout agent-kit main" { git -C $VGC_DIR checkout main }
    Invoke-RequiredNative "Pull agent-kit main" { git -C $VGC_DIR pull --ff-only origin main }
} elseif (Test-Path $VGC_DIR) {
    $overwrite = Read-Host "Directory $VGC_DIR exists but is not a git repo. Overwrite? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") { exit 0 }
    Remove-PathSafe $VGC_DIR
    Invoke-RequiredNative "Clone agent-kit" { git clone --quiet $REPO_URL $VGC_DIR }
    Write-Host "[vgc-agent-kit] Cloned successfully."
} else {
    Invoke-RequiredNative "Clone agent-kit" { git clone --quiet $REPO_URL $VGC_DIR }
    Write-Host "[vgc-agent-kit] Cloned successfully."
}

# ──────────────────────────────────────────
# Step 8: Clone/update workspace
# ──────────────────────────────────────────
$WORKSPACE_URL = "https://github.com/vgcorpvn/vgc-agent-workspace.git"

if (Test-Path "$WORKSPACE_DIR\.git") {
    Write-Host "[vgc-agent-kit] Workspace already exists — pulling latest..."
    Invoke-RequiredNative "Pull workspace" { git -C $WORKSPACE_DIR pull --ff-only }
} elseif (Test-Path $WORKSPACE_DIR) {
    $overwriteWs = Read-Host "Workspace exists but is not a git repo. Overwrite? (y/N)"
    if ($overwriteWs -ne "y" -and $overwriteWs -ne "Y") {
        Write-Host "[vgc-agent-kit] Skipping workspace setup."
    } else {
        Remove-PathSafe $WORKSPACE_DIR
        Invoke-RequiredNative "Clone workspace" { git clone --quiet $WORKSPACE_URL $WORKSPACE_DIR }
        Write-Host "[vgc-agent-kit] Workspace cloned successfully."
    }
} else {
    Invoke-RequiredNative "Clone workspace" { git clone --quiet $WORKSPACE_URL $WORKSPACE_DIR }
    Write-Host "[vgc-agent-kit] Workspace cloned successfully."
}

# ──────────────────────────────────────────
# Step 9: Scout token (optional) — source repos (read-only)
# ──────────────────────────────────────────
$skipScout = $false

if ($ghInstalled) {
    $scoutCheck = Invoke-NativeOutput { gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' }
    if ($scoutCheck.ExitCode -eq 0 -and $scoutCheck.Output) {
        Write-Host "[vgc-agent-kit] Token already has source repo access — no separate token needed."
        if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
        & gh auth token -h github.com 2>$null | Out-File -FilePath $SCOUT_TOKEN_FILE -Encoding ascii -NoNewline
        $skipScout = $true
    }
}

if (-not $skipScout -and (Test-Path $SCOUT_TOKEN_FILE)) {
    $existing = Get-Content $SCOUT_TOKEN_FILE -Raw -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            $env:GH_TOKEN = $existing.Trim()
            $check = Invoke-NativeOutput { gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' }
        } finally {
            Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        }
        if ($check.ExitCode -eq 0 -and $check.Output) {
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

    $SCOUT_PAT = Read-SecretText "Enter scout token (Enter to skip)"

    if (-not [string]::IsNullOrWhiteSpace($SCOUT_PAT)) {
        try {
            $env:GH_TOKEN = $SCOUT_PAT
            $check = Invoke-NativeOutput { gh api repos/vgcorpvn/mobile.vhandicap.com --jq '.name' }
        } finally {
            Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        }

        if ($check.ExitCode -eq 0 -and $check.Output) {
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
        Remove-PathSafe $_.FullName
        Write-Host "[vgc-agent-kit] Removed stale skill: $($_.Name)"
    }
}

Get-ChildItem -Path "$VGC_DIR\skills" -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillPath = $_.FullName
    $linkPath = Join-Path $CLAUDE_SKILLS_DIR $skillName

    if (-not (Test-Path "$skillPath\SKILL.md")) { return }
    if (Test-Path $linkPath) { Remove-PathSafe $linkPath }

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
