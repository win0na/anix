#Requires -Version 5.1
<#
.SYNOPSIS
Prepare Windows for the anix NixOS-WSL host.

.DESCRIPTION
Updates WSL, writes .wslconfig, opens TCP 2049 for the NixOS VM, downloads
and verifies the NixOS-WSL image, installs it, runs the first switch, and
registers the logon task. It never unregisters or deletes a distribution.
If the NixOS distribution already exists, the install step is skipped and the
remaining steps run again.

.PARAMETER Yes
Accept the prompts.

.PARAMETER ImageUrl
NixOS-WSL image URL. Default the 2605.7.2 nixos.wsl asset.

.PARAMETER ImageSha256
Expected SHA-256 of the image. Default the published 2605.7.2 digest.
#>
param(
  [switch]$Yes,
  [switch]$SkipWslUpdate,
  [switch]$SkipFirewall,
  [string]$ImageUrl = "https://github.com/nix-community/NixOS-WSL/releases/download/2605.7.2/nixos.wsl",
  [string]$ImageSha256 = "e7180ad555fdcb8e1e057e2ef056de467603a5e502ff8531053738371be3f6b9"
)

$ErrorActionPreference = "Stop"
$Distro = "NixOS"

function Confirm([string]$Message) {
  if ($Yes) { return $true }
  $answer = Read-Host "$Message [Y/n]"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
  return $answer -match '^[Yy]'
}

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  throw "Run this script as Administrator."
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

  if (Confirm "Open TCP 8080 for the WSL VM (code-server)?") {
    $ruleName = "WSL-code-server-8080"
    $existingRule = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
    if (-not $existingRule) {
      New-NetFirewallHyperVRule `
        -Name $ruleName `
        -DisplayName "WSL code-server TCP 8080" `
        -Direction Inbound `
        -Action Allow `
        -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
        -Protocol TCP `
        -LocalPorts 8080
    }
  }
}

$savedPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$distros = @(wsl --list --quiet 2>$null) -replace "`0", ""
$ErrorActionPreference = $savedPreference
$distroExists = $distros -contains $Distro
if ($distroExists) {
  if (-not (Confirm "$Distro already exists. Skip the install and continue?")) {
    throw "Install cancelled."
  }
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
    Invoke-WebRequest -Uri $ImageUrl -OutFile $part
    $actual = (Get-FileHash $part -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
      Remove-Item $part -Force
      throw "image checksum mismatch: $actual"
    }
    Move-Item $part $image -Force
  }
  if (-not (Confirm "Install $Distro from $image?")) {
    throw "Install cancelled."
  }
  wsl --shutdown
  wsl --install --from-file $image --no-launch
  if ($LASTEXITCODE -ne 0) { throw "wsl --install failed" }
}

$needsFirstSwitch = -not $distroExists
if ($distroExists) {
  $savedPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  wsl -d $Distro -u root -- id winona *> $null
  $needsFirstSwitch = ($LASTEXITCODE -ne 0)
  $ErrorActionPreference = $savedPreference
}

if ($needsFirstSwitch) {
  Write-Host "==> first switch in $Distro"
  wsl -d $Distro -u nixos -- bash -lc "set -euo pipefail; rm -rf /tmp/anix; export PATH=/nix/var/nix/profiles/default/bin:`$PATH; nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git -c git clone https://github.com/win0na/anix.git /tmp/anix; rm -f /tmp/anix/secrets/secrets.yaml; sudo NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild switch --flake /tmp/anix#anix"
  if ($LASTEXITCODE -ne 0) { throw "the first NixOS switch failed" }
} else {
  Write-Host "==> $Distro is already configured; skipping the first switch"
}

Write-Host "==> clone the repository for winona"
wsl -d $Distro -u winona -- bash -lc "set -euo pipefail; mkdir -p ~/src; if [ ! -d ~/src/anix/.git ]; then git clone https://github.com/win0na/anix.git ~/src/anix; fi"

$taskName = "anix-wsl"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
  $action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -u winona --exec /bin/true"
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
}

Write-Host ""
Write-Host "Windows is ready."
Write-Host "Next: open $Distro as winona, copy the age key, builder key, and secrets file, then run:"
Write-Host "  ~/src/anix/scripts/bootstrap"
