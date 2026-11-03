# Push the Ubuntu Touch bring-up payload to the X6812 and optionally build the
# images on the device.
#
#   powershell -File tools\push-install.ps1            # push + build on /data
#   powershell -File tools\push-install.ps1 -NoRun     # push only
#
# The device must be rooted (adb root) and have ~8 GB free on /data.

param(
    [switch]$NoRun,
    [string]$Target = "/data",
    [string]$Size = "8G"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$proj = $root

# Everything lands in /data, which only a root adbd can write. The setting is
# reset when the phone reboots: Settings -> System -> Developer options ->
# "Rooted debugging".
$id = (adb shell id 2>$null) -join ""
if ($id -notmatch "uid=0") {
    Write-Host "adb shell is not root: $id"
    throw "enable Settings -> System -> Developer options -> Rooted debugging, then 'adb root'"
}

$src = @{
    "/data/ut-rootfs.tar.gz"   = "$proj\out\rootfs\focal-arm64-rootfs.tar.gz"
    "/data/android-rootfs.img" = "$proj\out\rootfs\merlin-dev\system\var\lib\lxc\android\android-rootfs.img"
    "/data/install-x6812.sh"   = "$proj\tools\install-x6812.sh"
    "/data/check-rootfs.sh"    = "$proj\tools\check-rootfs.sh"
    "/data/track-t.sh"         = "$proj\tools\track-t.sh"
}

foreach ($dst in $src.Keys) {
    $local = $src[$dst]
    if (-not (Test-Path $local)) { throw "missing local file: $local" }
    $mb = [math]::Round((Get-Item $local).Length / 1MB, 1)
    Write-Host "==> push $local ($mb MB) -> $dst"
    adb push $local $dst
    if ($LASTEXITCODE -ne 0) { throw "adb push failed for $local" }
}

$dirs = @{
    "/data/ut-overlay" = "$proj\device\infinix\X6812\overlay"
    "/data/ut-modules" = "$proj\device\infinix\X6812\prebuilt\modules"
}

foreach ($dst in $dirs.Keys) {
    $local = $dirs[$dst]
    if (-not (Test-Path $local)) { throw "missing local dir: $local" }
    Write-Host "==> push $local -> $dst"
    adb shell "rm -rf $dst"
    adb push "$local/." "$dst/"
    if ($LASTEXITCODE -ne 0) { throw "adb push failed for $local" }
}

Write-Host "==> vendor.img on device:"
adb shell "ls -l /data/vendor.img"

if ($NoRun) {
    Write-Host "`nPush done. Run on the device:"
    Write-Host "  adb shell sh /data/install-x6812.sh $Target $Size"
    exit 0
}

Write-Host "`n==> building images on the device (10-20 min)"
adb shell "sh /data/install-x6812.sh $Target $Size"
