# Flash the Track T boot image and wait for the phone to come back.
#
#   powershell -File tools\flash-track-t.ps1
#   powershell -File tools\flash-track-t.ps1 -Restore
#
# `fastboot boot` crashes this bootloader (ro.boot.bootreason=lk_crash), so the
# only way to start a custom boot image is to flash boot_a. Everything here is
# reversible: -Restore flashes the Stage 1 stock dump back.
#
# If the halium initramfs panics it sits on the last screen line and does not
# reboot. To get back to fastboot: hold Volume Down and connect USB (or press
# power), then run this script with -Restore.

param(
    [switch]$Restore,
    [string]$Image = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Image) {
    $Image = if ($Restore) { "out\stock-boot_a.img" } else { "out\halium-boot-sd.img" }
}
$img = Join-Path $root $Image
if (-not (Test-Path $img)) { throw "missing boot image: $img" }

$hash = (Get-FileHash $img -Algorithm SHA256).Hash
Write-Host "==> image  $Image"
Write-Host "    size   $((Get-Item $img).Length) B"
Write-Host "    sha256 $hash"
if (-not $Restore) {
    Write-Host ""
    Write-Host "    This replaces boot_a. Rollback: tools\flash-track-t.ps1 -Restore"
    Write-Host "    Make sure the microSD card is inserted - the cmdline is datapart=/dev/mmcblk1."
}
Write-Host ""

# get the phone into fastboot from either Android or an already-open bootloader
$fw = (fastboot devices 2>$null | Select-String "072963119P013174")
if (-not $fw) {
    $ad = (adb devices 2>$null | Select-String "072963119P013174")
    if ($ad) {
        Write-Host "==> rebooting to bootloader"
        adb reboot bootloader | Out-Null
    } else {
        Write-Host "==> phone not on USB; waiting for fastboot (hold Volume Down and connect USB)"
    }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if (fastboot devices 2>$null | Select-String "072963119P013174") { break }
        if ($i -eq 59) { throw "no fastboot device after 60 s" }
    }
}

Write-Host "==> flashing boot_a"
fastboot flash boot $img
if ($LASTEXITCODE -ne 0) { throw "fastboot flash failed" }

Write-Host "==> rebooting"
fastboot reboot | Out-Null

if ($Restore) {
    Write-Host ""
    Write-Host "stock boot restored; the phone should boot Android again"
    exit 0
}

Write-Host ""
Write-Host "==> waiting for the phone to leave fastboot"
Start-Sleep -Seconds 5
$gone = $false
for ($i = 0; $i -lt 24; $i++) {
    if (-not (fastboot devices 2>$null | Select-String "072963119P013174")) { $gone = $true; break }
    Start-Sleep -Seconds 5
}
Write-Host "    left fastboot: $gone"
Write-Host ""
Write-Host "The panel stays dark until Lomiri starts (this kernel has no CONFIG_VT)."
Write-Host "First boot needs 5-15 minutes; do not judge before 15."
Write-Host ""
Write-Host "Then, with the card still inserted and Android booted:"
Write-Host "  powershell -File tools\pull-card-log.ps1"
