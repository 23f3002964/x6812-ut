# Collect the logs from a failed Ubuntu Touch boot attempt.
#
#   powershell -File tools\get-boot-logs.ps1
#   powershell -File tools\get-boot-logs.ps1 -Tag before-vendor-fix
#
# Run it while the phone is booted into Android (the normal system). The Halium
# boot writes its initramfs messages to pstore/ramoops, which survives the
# reboot; `adb exec-out` is used so the bytes are not rewritten by PowerShell.

param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ($Tag) { $stamp = "$stamp-$Tag" }
$dir = Join-Path $root "out\boot-logs\$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function Grab([string]$name, [string]$remote) {
    $local = Join-Path $dir $name
    Write-Host "==> $remote -> $local"
    $bytes = & adb exec-out "cat $remote" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $bytes) {
        Write-Host "    (empty or not present)"
        return
    }
    # adb exec-out gives us raw bytes; PowerShell 5.1 hands them over as strings
    # already, so write them back as UTF-8 without a BOM.
    [System.IO.File]::WriteAllText($local, ($bytes -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

Grab "pstore-console-ramoops-0.txt" "/sys/fs/pstore/console-ramoops-0"
Grab "pstore-dmesg-ramoops-0.txt"   "/sys/fs/pstore/dmesg-ramoops-0"
Grab "last-kmsg.txt"                "/proc/last_kmsg"

Write-Host "==> dmesg -> dmesg.txt"
& adb exec-out dmesg | Out-File -FilePath (Join-Path $dir "dmesg.txt") -Encoding utf8

Write-Host "`n==> summary of the Halium messages"
$f = Join-Path $dir "pstore-console-ramoops-0.txt"
if (Test-Path $f) {
    Select-String -Path $f -Pattern "Halium|halium|PANIC|Error|error|Failed|failed" |
        Select-Object -Last 60 |
        ForEach-Object { $_.Line }
} else {
    Write-Host "no pstore log - either the boot got further than the initramfs,"
    Write-Host "or ramoops is disabled. Check the screen / adb devices."
}

Write-Host "`nlogs in $dir"
