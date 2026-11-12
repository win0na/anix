#Requires -Version 5.1
<#
.SYNOPSIS
Prepare Windows for the anix NixOS-WSL host.

.DESCRIPTION
Updates WSL, writes .wslconfig, opens TCP 2049 for the NixOS VM, downloads
and verifies the NixOS-WSL image, installs it, runs the first switch, and
registers the logon task. It never unregisters or deletes a distribution.
If the NixOS distribution already exists, the install step is skipped and the
remaining steps run again. Unless NoBootstrap is set, the helper finishes by
running the anix bootstrap inside the new distribution.

.PARAMETER Yes
Accept the prompts.

.PARAMETER ImageUrl
NixOS-WSL image URL. Default the 2605.7.2 nixos.wsl asset.

.PARAMETER ImageSha256
Expected SHA-256 of the image. Default the published 2605.7.2 digest.

.PARAMETER RepoUrl
Git URL of the anix fork to clone. Default $env:ANIX_REPO_URL, then
https://github.com/win0na/anix.git.

.PARAMETER MacUser
macOS account short name for amac. Written to users.nix before the bootstrap.

.PARAMETER ProjectsDir
Project root. A relative name stays under the anix home; an absolute path is
used as-is. Written to users.nix before the first switch.

.PARAMETER NoBootstrap
Stop after the clone. Do not run scripts/bootstrap inside the new distribution.

.PARAMETER NoMac
Do not run scripts/bootstrap-mac-remote after the anix bootstrap.
#>
param(
  [switch]$Yes,
  [switch]$SkipWslUpdate,
  [switch]$SkipFirewall,
  [switch]$NoShutdown,
  [switch]$NoFirstSwitch,
  [switch]$NoClone,
  [switch]$NoBootstrap,
  [switch]$NoMac,
  [switch]$NoTask,
  [string]$DistroName = "NixOS",
  [string]$AnixUser = "",
  [string]$MacUser = "",
  [string]$ProjectsDir = "",
  [string]$RepoUrl = "",
  [string]$ImageUrl = "https://github.com/nix-community/NixOS-WSL/releases/download/2605.7.2/nixos.wsl",
  [string]$ImageSha256 = "e7180ad555fdcb8e1e057e2ef056de467603a5e502ff8531053738371be3f6b9",
  [string]$ImagePath = "",
  [string]$Location = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# Without this, PowerShell 5.1 decodes wsl.exe output as OEM and the version
# check below silently never matches.
$env:WSL_UTF8 = "1"
$logPath = Join-Path $env:TEMP "anix-bootstrap-windows.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { $logPath = "" }
# The elevated window closes on exit, so print the failure and keep the log.
trap {
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
  Write-Host ""
  Write-Host "ERROR: $($_.Exception.Message)"
  if ($logPath) { Write-Host "Log: $logPath" }
  Write-Host "Fix the error above, then rerun this script."
  exit 1
}
$Distro = $DistroName
if ([string]::IsNullOrWhiteSpace($Distro)) { throw "DistroName is empty" }

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  throw "Run this script from an elevated PowerShell (Run as administrator)."
}

if ([string]::IsNullOrWhiteSpace($RepoUrl)) { $RepoUrl = $env:ANIX_REPO_URL }
if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
  if (-not $Yes) {
    while ([string]::IsNullOrWhiteSpace($RepoUrl)) {
      $RepoUrl = Read-Host "Fork URL (create one at https://github.com/win0na/anix/fork)"
    }
  }
}
$RepoQuoted = "'" + $RepoUrl.Replace("'", "'\''") + "'"
if ($Yes -and [string]::IsNullOrWhiteSpace($RepoUrl) -and -not ($NoClone -and $NoFirstSwitch)) {
  throw "RepoUrl is required with -Yes; create a fork first."
}

if ([string]::IsNullOrWhiteSpace($AnixUser)) {
  if ($Yes) {
    $AnixUser = ($env:USERNAME -replace '[^A-Za-z0-9._-]', '').ToLower()
    if ($AnixUser -match '^[0-9]') { $AnixUser = "u$AnixUser" }
  } else {
    $AnixUser = Read-Host "Linux username for anix"
  }
}
if ([string]::IsNullOrWhiteSpace($AnixUser)) { throw "AnixUser is empty" }
if ($AnixUser -notmatch '^[A-Za-z0-9._-]+$') { throw "AnixUser has invalid characters: $AnixUser" }

if ([string]::IsNullOrWhiteSpace($MacUser)) {
  if ($Yes) {
    $MacUser = "amac"
  } else {
    $MacUser = Read-Host "macOS short name for amac (run whoami on the Mac)"
  }
}
if ([string]::IsNullOrWhiteSpace($MacUser)) { throw "MacUser is empty" }
if ($MacUser -notmatch '^[A-Za-z0-9._-]+$') { throw "MacUser has invalid characters: $MacUser" }

if ([string]::IsNullOrWhiteSpace($ProjectsDir)) {
  if ($Yes) {
    $ProjectsDir = "src"
  } else {
    $ProjectsDir = Read-Host "Project directory [src]"
    if ([string]::IsNullOrWhiteSpace($ProjectsDir)) { $ProjectsDir = "src" }
  }
}
if ($ProjectsDir -notmatch '^[A-Za-z0-9._/-]+$' -or $ProjectsDir.Contains("..") -or $ProjectsDir -eq "/" -or $ProjectsDir -eq "." -or $ProjectsDir.EndsWith("/")) {
  throw "ProjectsDir is invalid: $ProjectsDir"
}
$projectSegments = $ProjectsDir -split "/"
if ($projectSegments -contains "." -or $projectSegments -contains "..") {
  throw "ProjectsDir must not contain . or .. segments: $ProjectsDir"
}
if ($ProjectsDir.StartsWith("/") -and -not ($ProjectsDir.StartsWith("/home/") -or $ProjectsDir.StartsWith("/mnt/"))) {
  throw "ProjectsDir must be under /home or /mnt: $ProjectsDir"
}
$projectName = ($projectSegments[-1]).ToLower()
if ($projectName -in @("applications","desktop","documents","downloads","library","movies","music","pictures","public","system","users",".config",".ssh")) {
  throw "ProjectsDir must not use a protected home directory: $ProjectsDir"
}
if ($ProjectsDir -eq "/home/$AnixUser") {
  throw "ProjectsDir must not be the anix home: $ProjectsDir"
}

function Confirm([string]$Message) {
  if ($Yes) { return $true }
  $answer = Read-Host "$Message [Y/n]"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
  return $answer -match '^[Yy]'
}

$savedPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
wsl --status *> $null
$wslReady = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $savedPreference
if (-not $wslReady) {
  if (-not (Confirm "WSL is not installed. Install it now? A reboot may be required.")) {
    throw "WSL is required."
  }
  wsl --install --no-distribution
  $installExit = $LASTEXITCODE
  if ($installExit -ne 0 -and $installExit -ne 3010) { throw "wsl --install failed with exit code $installExit" }
  Write-Host "WSL is installed."
  $ErrorActionPreference = "Continue"
  wsl --status *> $null
  $wslReady = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $savedPreference
  if (-not $wslReady) {
    Write-Host "Reboot Windows, then run this script again."
    exit 0
  }
  Write-Host "No reboot needed; continuing."
}

if (-not $SkipWslUpdate) {
  if (Confirm "Update WSL now?") {
    wsl --update
    if ($LASTEXITCODE -ne 0) { throw "wsl --update failed" }
  }
}

$savedPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$wslVersion = (wsl --version 2>$null | Select-String -Pattern 'WSL version:\s*([0-9.]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$ErrorActionPreference = $savedPreference
if ($wslVersion) {
  $current = [version]$wslVersion
  if ($current -lt [version]"2.4.4") {
    Write-Warning "WSL $wslVersion is older than 2.4.4; --from-file may fail."
  }
}

$wslconfig = Join-Path $env:UserProfile ".wslconfig"
$content = @"
[wsl2]
memory=16GB
processors=8
swap=8GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true

[general]
instanceIdleTimeout=-1

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@

if (Test-Path $wslconfig) {
  $existing = Get-Content -Raw $wslconfig
  if ($existing.Trim() -ne $content.Trim()) {
    if (Confirm "$wslconfig differs. Back it up and replace it?") {
      $backup = "$wslconfig.before-anix.$(Get-Date -Format yyyyMMddHHmmss)"
      Copy-Item $wslconfig $backup -Force
      Set-Content -Path $wslconfig -Value $content -Encoding ASCII
    }
  }
} else {
  Set-Content -Path $wslconfig -Value $content -Encoding ASCII
}

if (-not $SkipFirewall) {
  if (Confirm "Open TCP 2049 for the WSL VM?") {
    $ruleName = "WSL-nfsd-2049"
    $existingRule = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
    if (-not $existingRule) {
      New-NetFirewallHyperVRule `
        -Name $ruleName `
        -DisplayName "WSL nfsd TCP 2049" `
        -Direction Inbound `
        -Action Allow `
        -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
        -Protocol TCP `
        -LocalPorts 2049
    }
  }

  $staleRule = Get-NetFirewallHyperVRule -Name "WSL-code-server-8080" -ErrorAction SilentlyContinue
  if ($staleRule) {
    Write-Host "==> removing the stale WSL-code-server-8080 rule"
    Remove-NetFirewallHyperVRule -Name "WSL-code-server-8080"
  }
}

$savedPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
wsl --list --quiet 2>$null | Out-Null
$distros = @(wsl --list --quiet 2>$null) -replace "`0", ""
$ErrorActionPreference = $savedPreference
$distroExists = $distros -contains $Distro
$needsFirstSwitch = $false
if ($distroExists) {
  $savedPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  wsl -d $Distro -u root --exec id $AnixUser *> $null
  $needsFirstSwitch = ($LASTEXITCODE -ne 0)
  $ErrorActionPreference = $savedPreference
  if ($needsFirstSwitch) {
    if ($Yes) {
      throw "A distribution named $Distro already exists and has no $AnixUser. Pass -DistroName with a different name, or remove that distribution first."
    }
    if (-not (Confirm "$Distro exists without $AnixUser. The first switch will replace its configuration. Continue?")) {
      throw "Install cancelled."
    }
  } elseif (-not (Confirm "$Distro already exists. Skip the install and continue?")) {
    throw "Install cancelled."
  }
} else {
  if ($ImagePath) {
    $image = $ImagePath
    if (-not (Test-Path $image)) { throw "image not found: $image" }
  } else {
    $image = Join-Path $env:TEMP "nixos.wsl"
    $expected = $ImageSha256.ToLower()
    if (Test-Path $image) {
      $actual = (Get-FileHash $image -Algorithm SHA256).Hash.ToLower()
      if ($actual -ne $expected) {
        Remove-Item $image -Force
      }
    }
    if (-not (Test-Path $image)) {
      Write-Host "==> downloading $ImageUrl"
      $part = "$image.part"
      Invoke-WebRequest -Uri $ImageUrl -OutFile $part -UseBasicParsing
      $actual = (Get-FileHash $part -Algorithm SHA256).Hash.ToLower()
      if ($actual -ne $expected) {
        Remove-Item $part -Force
        throw "image checksum mismatch: $actual"
      }
      Move-Item $part $image -Force
    }
  }
  $shutdownNote = ""
  if (-not $NoShutdown) { $shutdownNote = " This stops any running WSL distribution." }
  if (-not (Confirm "Install $Distro from $image?$shutdownNote")) {
    throw "Install cancelled."
  }
  if (-not $NoShutdown) { wsl --shutdown }
  $installArgs = @("--install", "--from-file", $image, "--name", $Distro, "--no-launch")
  if ($Location) { $installArgs += @("--location", $Location) }
  & wsl @installArgs
  if ($LASTEXITCODE -ne 0) { throw "wsl --install failed with exit code $LASTEXITCODE" }
  $needsFirstSwitch = $true
}
if ($NoFirstSwitch) {
  Write-Host "==> first switch skipped (NoFirstSwitch)"
  $needsFirstSwitch = $false
}

if ($needsFirstSwitch) {
  Write-Host "==> first switch in $Distro"
  wsl -d $Distro -u nixos --exec bash -lc "set -euo pipefail; rm -rf /tmp/anix; export PATH=/nix/var/nix/profiles/default/bin:`$PATH; nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git -c git clone $RepoQuoted /tmp/anix; rm -f /tmp/anix/secrets/secrets.yaml; printf '{\n  anix = \x22%s\x22;\n  amac = \x22%s\x22;\n  projectsDir = \x22%s\x22;\n}\n' '$AnixUser' '$MacUser' '$ProjectsDir' > /tmp/anix/users.nix; sudo env PATH=`"`$PATH`" NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild boot --flake /tmp/anix#anix"
  if ($LASTEXITCODE -ne 0) { throw "the first NixOS switch failed; read the error above, then rerun this script." }
  wsl --terminate $Distro
  wsl -d $Distro -u $AnixUser --exec true
  if ($LASTEXITCODE -ne 0) { throw "the new distribution did not start as $AnixUser; rerun this script." }
} elseif (-not $NoFirstSwitch) {
  Write-Host "==> $Distro is already configured; skipping the first switch"
}

if (-not $NoClone) {
  Write-Host "==> clone the repository for $AnixUser"
  wsl -d $Distro -u $AnixUser --exec bash -lc "set -euo pipefail; mkdir -p ~/.config; if [ ! -d ~/.config/anix/.git ]; then git clone $RepoQuoted ~/.config/anix; fi"
  if ($LASTEXITCODE -ne 0) { throw "git clone failed for $RepoUrl; check the URL and your access, then rerun this script." }
  $usersScript = @'
set -euo pipefail
f="$HOME/.config/anix/users.nix"
need=0
if [ ! -f "$f" ]; then
  need=1
elif ! grep -q 'anix = "__ANIX__"' "$f"; then
  need=1
elif grep -q 'amac = "amac"' "$f" && [ "__MAC__" != "amac" ]; then
  need=1
fi
if [ "$need" -eq 1 ]; then
  dir="__DIR__"
  if [ -f "$f" ]; then
    cur=$(sed -n 's/.*projectsDir *= *"\([^"]*\)".*/\1/p' "$f" | head -1)
    [ -n "$cur" ] && dir=$cur
  fi
  printf '{\n  anix = "%s";\n  amac = "%s";\n  projectsDir = "%s";\n}\n' "__ANIX__" "__MAC__" "$dir" > "$f"
fi
'@
  $usersScript = $usersScript.Replace("__ANIX__", $AnixUser).Replace("__MAC__", $MacUser).Replace("__DIR__", $ProjectsDir)
  wsl -d $Distro -u $AnixUser --exec bash -lc $usersScript
  if ($LASTEXITCODE -ne 0) { throw "could not write users.nix in ~/.config/anix; rerun this script." }
}

if (-not $NoTask) {
  $taskName = "anix-wsl"
  $action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -u $AnixUser --exec /run/current-system/sw/bin/sleep infinity"
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
  try { Start-ScheduledTask -TaskName $taskName } catch {
    Write-Host "==> could not start $taskName; start it from Task Scheduler if NFS must come up now"
  }
}

if (-not $NoBootstrap -and -not $NoClone) {
  Write-Host "==> running the anix bootstrap"
  $bootstrapArgs = "--host anix"
  if ($Yes) { $bootstrapArgs += " --yes" }
  wsl -d $Distro -u $AnixUser --exec bash -lc "cd ~/.config/anix && exec ./scripts/bootstrap $bootstrapArgs"
  if ($LASTEXITCODE -ne 0) { throw "the anix bootstrap failed; rerun: wsl -d $Distro -u $AnixUser --exec bash -lc 'cd ~/.config/anix && ./scripts/bootstrap --host anix'" }

  if (-not $NoMac) {
    $tailscale = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
    if (-not $tailscale -or $tailscale.Status -ne "Running") {
      throw "Tailscale is not running on Windows. Sign in to Tailscale, confirm the anix node is up, then rerun this script."
    }
    Write-Host "==> preparing the Mac"
    $macArgs = ""
    if ($Yes) { $macArgs = "--yes" }
    wsl -d $Distro -u $AnixUser --exec bash -lc "cd ~/.config/anix && exec ./scripts/bootstrap-mac-remote $macArgs"
    if ($LASTEXITCODE -ne 0) { throw "the Mac bootstrap failed; enable Remote Login, then run: wsl -d $Distro -u $AnixUser --exec bash -lc 'cd ~/.config/anix && ./scripts/bootstrap-mac-remote'" }
  }
  Write-Host ""
  Write-Host "Done. anix is running in $Distro."
} elseif ($NoBootstrap) {
  Write-Host ""
  Write-Host "Windows is ready. The distribution and checkout are in place."
  Write-Host "Next: wsl -d $Distro -u $AnixUser --exec bash -lc 'cd ~/.config/anix && ./scripts/bootstrap --host anix'"
} else {
  Write-Host ""
  Write-Host "Windows is ready; the caller continues the bootstrap."
}

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
