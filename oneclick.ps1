<#
  oneclick.ps1 - restore a whole DSH setup on a fresh Windows machine.

  Double-click 恢复DSH.cmd (or 一键恢复DSH.cmd). It will:
    1. install the pinned DeepSeek Harness build if it is not installed
    2. authenticate to the private backup repository (gh token or a PAT)
    3. clone it once and replay the snapshot into %USERPROFILE%\.dsh
    4. register the daily backup task (22:00 + logon catch-up)
    5. offer to start DSH

  Credentials, OAuth grants and the speech model are never in the backup:
  sign in once and re-enter MCP secrets afterwards.

  ASCII-only on purpose: Windows PowerShell 5.1 parses BOM-less .ps1 as ANSI.
#>

[CmdletBinding()]
param(
    [string]$BackupRepo = 'https://github.com/AiCoderChenweishi/dsh-backup.git',
    [string]$BackupRef = 'main',
    [string]$FeedUrl = 'https://download.deepseek.com/dsh-desk/feeds/win-x64/nightly.yml',
    [string]$Token,
    [switch]$DryRun,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$env:GIT_TERMINAL_PROMPT = '0'
$env:GH_PROMPT_DISABLED = '1'
$env:GIT_ASKPASS = 'echo'

function Write-Step([string]$m) { Write-Host ''; Write-Host ('== ' + $m) -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host ('   ok   ' + $m) -ForegroundColor Green }
function Write-Warn2([string]$m) { Write-Host ('   warn ' + $m) -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host ''; Write-Host ('FAILED: ' + $m) -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '  DSH one-click restore' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ('  machine : ' + $env:COMPUTERNAME)
Write-Host ('  target  : ' + (Join-Path $env:USERPROFILE '.dsh'))
if ($DryRun) { Write-Warn2 'DRY RUN: nothing will be installed or written' }

# ---------------------------------------------------------- preflight ------

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Fail 'git is not installed. Install Git for Windows, then run this again.'
}

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*DeepSeek*' })
if ($running.Count -gt 0 -and -not $DryRun) {
    Fail 'DeepSeek Harness is running. Close it completely, then run this again.'
}

function Get-InstallState {
    $state = [pscustomobject]@{ Installed = $false; Version = $null; Dir = $null }
    foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $hit = Get-ItemProperty $k -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like 'DeepSeek Harness*' } | Select-Object -First 1
        if ($hit) { $state.Installed = $true; $state.Version = $hit.DisplayVersion; $state.Dir = $hit.InstallLocation; break }
    }
    if (-not $state.Dir) {
        $c = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'
        if (Test-Path -LiteralPath (Join-Path $c 'DeepSeek Harness.exe')) {
            $state.Installed = $true; $state.Dir = $c
        }
    }
    return $state
}

function Get-Feed {
    param([string]$Url)
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 30 -UseBasicParsing
    $text = [System.Text.Encoding]::UTF8.GetString($resp.Content)
    $v = $null; $u = $null; $s = $null
    $m = [regex]::Match($text, '(?m)^\s*version:\s*([^\s]+)')
    if ($m.Success) { $v = $m.Groups[1].Value.Trim("'", '"') }
    $m = [regex]::Match($text, '(https://[^\s''"]+\.exe)')
    if ($m.Success) { $u = $m.Groups[1].Value }
    $m = [regex]::Match($text, '(?ms)^\s*sha512:\s*>?-?\s*\r?\n?\s*([A-Za-z0-9+/=]{40,})')
    if ($m.Success) { $s = $m.Groups[1].Value }
    return [pscustomobject]@{ Version = $v; Url = $u; Sha512 = $s }
}

function Get-Sha512([string]$Path) {
    $sha = [System.Security.Cryptography.SHA512]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try { $h = $sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }
    return [Convert]::ToBase64String($h)
}

# ------------------------------------------------------------ 1. install ----

$state = Get-InstallState
if ($state.Installed) {
    Write-Step ('DSH is already installed: ' + $state.Version)
} else {
    Write-Step 'resolving the installer from the update feed'
    $feed = Get-Feed $FeedUrl
    if (-not $feed.Url) { Fail 'could not resolve the installer URL from the feed' }
    Write-Host ('   version ' + $feed.Version)
    Write-Host ('   url     ' + $feed.Url)
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) (Split-Path -Leaf $feed.Url)
    if ($DryRun) {
        Write-Warn2 ('would download ' + $installer)
    } else {
        if (-not (Test-Path -LiteralPath $installer) -or (Get-Item -LiteralPath $installer).Length -lt 100MB) {
            Write-Step 'downloading DSH (about 276 MB)'
            $wc = New-Object System.Net.WebClient
            try { $wc.Headers.Add('User-Agent', 'dsh-oneclick/1'); $wc.DownloadFile($feed.Url, $installer) } finally { $wc.Dispose() }
        }
        if ($feed.Sha512) {
            $actual = Get-Sha512 $installer
            if ($actual -ne $feed.Sha512) { Fail 'installer checksum mismatch; download aborted' }
            Write-Ok 'checksum verified'
        }
        Write-Step 'installing silently'
        $p = Start-Process -FilePath $installer -ArgumentList '/S' -PassThru -Wait
        if ($p.ExitCode -ne 0) { Fail ('installer exited with ' + $p.ExitCode) }
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 2
            $state = Get-InstallState
            if ($state.Installed) { break }
        }
        if (-not $state.Installed) { Fail 'installer finished but DSH is not registered' }
        Write-Ok ('installed ' + $state.Version)
    }
}

# -------------------------------------------------------- 2. credentials ----

$token = $Token
if (-not $token) {
    $gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (-not (Test-Path -LiteralPath $gh)) { $gh = (Get-Command gh.exe -ErrorAction SilentlyContinue).Source }
    if (Test-Path -LiteralPath $gh) {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $gp = Start-Process -FilePath $gh -ArgumentList @('auth', 'token') -NoNewWindow -PassThru `
                -RedirectStandardOutput $tmp -RedirectStandardError ($tmp + '.err')
            # PS 5.1 leaves .ExitCode empty for some redirected children, so
            # trust the captured token rather than the exit code.
            if ($gp.WaitForExit(10000)) {
                $token = (Get-Content -LiteralPath $tmp -Raw -ErrorAction SilentlyContinue).Trim()
                if ($token) { Write-Ok 'using the GitHub CLI token' }
            } else {
                try { $gp.Kill() } catch { }
            }
        } catch { } finally { Remove-Item -LiteralPath $tmp, ($tmp + '.err') -Force -ErrorAction SilentlyContinue }
    }
}
if (-not $token -and -not $DryRun) {
    Write-Host ''
    Write-Host 'The backup repository is private.'

    $sec = Read-Host 'GitHub token (gho_/ghp_, repo scope). Leave empty to try SSH' -AsSecureString
    if ($sec.Length -gt 0) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

if ($token) {
    $cloneUrl = $BackupRepo -replace '^https://', ('https://x-access-token:' + $token + '@')
} else {
    if ($BackupRepo -match '^https://github\.com/(.+)$') {
        $cloneUrl = 'git@github.com:' + $Matches[1]
    } else {
        $cloneUrl = $BackupRepo
    }
    Write-Warn2 'no token: using the SSH key on this machine (must be added to GitHub)'
}

# ------------------------------------------------------------- 3. clone ----

$stage = Join-Path $env:USERPROFILE ('.dsh-oneclick-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
Write-Step 'cloning the backup repository (about 1 GB on the first run)'
if ($DryRun) {
    Write-Warn2 ('would clone into ' + $stage)
} else {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $savedGlobal = $env:GIT_CONFIG_GLOBAL
    $savedCount = $env:GIT_CONFIG_COUNT
    if ($token) {
        $emptyCfg = Join-Path $stage 'gitconfig-empty'
        Set-Content -LiteralPath $emptyCfg -Value '' -Encoding ASCII
        $env:GIT_CONFIG_GLOBAL = $emptyCfg
    }
    # long paths: the snapshot contains nested session paths beyond MAX_PATH
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'core.longpaths'
    $env:GIT_CONFIG_VALUE_0 = 'true'
    try {
        & git clone --branch $BackupRef --single-branch $cloneUrl (Join-Path $stage 'repo') 2>&1 | ForEach-Object { $_.ToString() }
        if ($LASTEXITCODE -ne 0) {
            # github.com:443 is blocked on some networks; ssh.github.com:443 is not.
            Remove-Item -LiteralPath (Join-Path $stage 'repo') -Recurse -Force -ErrorAction SilentlyContinue
            $sshUrl = $BackupRepo
            if ($sshUrl -match '^https://github\.com/(.+)$') { $sshUrl = 'ssh://git@ssh.github.com:443/' + $Matches[1] }
            Write-Warn2 'https clone failed; retrying over SSH (ssh.github.com:443, needs a key on GitHub)'
            & git clone --branch $BackupRef --single-branch $sshUrl (Join-Path $stage 'repo') 2>&1 | ForEach-Object { $_.ToString() }
        }
        if ($LASTEXITCODE -ne 0) { Fail 'git clone failed (token scope? repository name? network?)' }
    } finally {
        if ($token) { $env:GIT_CONFIG_GLOBAL = $savedGlobal }
        $env:GIT_CONFIG_COUNT = $savedCount
        Remove-Item Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
    }
    Write-Ok 'clone complete'
}

if ($DryRun) { Write-Warn2 'DRY RUN ends here'; exit 0 }

# ------------------------------------------------------------ 4. restore ----

$repo = Join-Path $stage 'repo'
$restore = Join-Path $repo 'backup\dsh-restore.ps1'
if (-not (Test-Path -LiteralPath $restore)) { Fail 'the snapshot has no backup\dsh-restore.ps1' }

Write-Step 'restoring the snapshot into the machine'
$restoreArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $restore,
    '-DshHome', (Join-Path $env:USERPROFILE '.dsh'),
    '-Ref', $BackupRef, '-SourceRoot', $repo, '-Force', '-SkipPnpm'
)
& powershell.exe @restoreArgs
if ($LASTEXITCODE -ne 0) { Fail ('restore failed (exit ' + $LASTEXITCODE + ')') }
Write-Ok 'snapshot restored'

# --------------------------------------------------------- 5. daily task ----

$register = Join-Path $env:USERPROFILE '.dsh\backup\register-task.ps1'
if (Test-Path -LiteralPath $register) {
    Write-Step 'registering the daily backup task'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $register
    if ($LASTEXITCODE -ne 0) { Write-Warn2 'task registration failed; run backup\register-task.ps1 manually' }
    else { Write-Ok 'task registered (22:00 + at logon catch-up)' }
}

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------- 6. finish ----

Write-Host ''
Write-Host 'Restore is complete. Two short manual steps remain:' -ForegroundColor Cyan
Write-Host '  1. Start DSH and sign in (credentials are never backed up).'
Write-Host '  2. After the first launch, double-click dsh.cmd in %USERPROFILE%\.dsh\backup'
Write-Host '     to install the profile dependencies (pnpm).'
Write-Host '  3. Settings > MCP: import backup\mcp-connector.export.json and re-enter secrets.'
Write-Host ''

if (-not $NoLaunch -and $state.Dir) {
    $exe = Join-Path $state.Dir 'DeepSeek Harness.exe'
    if (Test-Path -LiteralPath $exe) {
        Write-Host 'Starting DeepSeek Harness...' -ForegroundColor Cyan
        Start-Process -FilePath $exe | Out-Null
    }
}

Write-Host 'Done.' -ForegroundColor Green
exit 0
