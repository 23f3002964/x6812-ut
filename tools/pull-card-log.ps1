# Pull the bring-up logs that the X6812 port writes to the data partition.
#
#   powershell -File tools\pull-card-log.ps1
#   powershell -File tools\pull-card-log.ps1 -Device /dev/block/mmcblk1
#
# Run it while Android is booted and the test card is inserted. It reads only
# the ext4 blocks that hold the log files (tools/ext4-get.py), so nothing big is
# copied over USB. No rootfs mount and no SELinux workaround is needed.
#
# It also saves /proc/last_kmsg (MTK ram_console): that is the only channel when
# the boot dies before /userdata mounts.

param(
    [string]$Device = "/dev/block/mmcblk1",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $OutDir) {
    $OutDir = Join-Path $root ("out\boot-logs\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# MTK ram_console: survives the failed boot, needs neither the card nor a rootfs
# mount, and is the only channel before the data partition comes up.
Write-Host "==> /proc/last_kmsg"
$kmsg = adb shell cat /proc/last_kmsg 2>$null
if ($LASTEXITCODE -eq 0 -and $kmsg) {
    $kmsg | Out-File -FilePath (Join-Path $OutDir "last_kmsg.txt") -Encoding utf8
    Write-Host "    saved last_kmsg.txt ($($kmsg.Count) lines)"
} else {
    Write-Host "    (empty or unreadable - adb root helps)"
}

# A card that is not inserted still has a /sys/class/block node, with size 0.
$leaf = Split-Path $Device -Leaf
$prev = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
$sectors = ((adb shell "cat /sys/class/block/$leaf/size" 2>$null) -join "").Trim()
$ErrorActionPreference = $prev

$haveCard = $false
if ($sectors -match '^\d+$' -and [int64]$sectors -gt 0) { $haveCard = $true }

$logs = @(
    @{ Remote = "/x6812-boot.log";    Local = "x6812-boot.log" },
    @{ Remote = "/x6812-journal.log"; Local = "x6812-journal.log" }
)

$got = 0
if (-not $haveCard) {
    Write-Host "==> $Device is not present (no card in the slot); skipping card logs"
} else {
    foreach ($l in $logs) {
        $local = Join-Path $OutDir $l.Local
        Write-Host "==> $($l.Remote) -> $local"
        # PowerShell 5.1 turns native stderr into a terminating error when
        # $ErrorActionPreference is Stop, so relax it around the helper.
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $text = & python (Join-Path $root "tools\ext4-get.py") --adb $Device cat $l.Remote 2>$null
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($rc -ne 0 -or -not $text) {
            Write-Host "    (not present - did the data partition mount?)"
            continue
        }
        $text | Out-File -FilePath $local -Encoding utf8
        $got++
    }
}

if ($got -eq 0) {
    Write-Host ""
    Write-Host "No card log found on $Device."
    Write-Host "The card may not be inserted, or the boot never mounted /userdata."
    Write-Host "Check last_kmsg.txt in $OutDir first: it is the only kernel channel"
    Write-Host "before the data partition mounts."
} else {
    Write-Host ""
    Write-Host "logs in $OutDir"
}
