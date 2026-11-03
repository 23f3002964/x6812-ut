$ErrorActionPreference = "Continue"
$url = "https://system-image.ubports.com/pool/rootfs-dedb4c5396ccb61421f0355574a111dd275cf6f59d86e57bf217482b89abcb82.tar.xz"
$dir = "C:\Users\tanisha\projects\x6812-ut\out\rootfs"
$parts = Join-Path $dir "parts"
$out = Join-Path $dir "focal-arm64-rootfs.tar.xz"
$total = 471726476
$chunk = 8MB
New-Item -ItemType Directory -Force $parts | Out-Null

$count = [Math]::Ceiling($total / $chunk)
"parts: $count x 8 MB, total $total bytes"

for ($i = 0; $i -lt $count; $i++) {
    $start = $i * $chunk
    $end = [Math]::Min($start + $chunk - 1, $total - 1)
    $want = $end - $start + 1
    $dest = Join-Path $parts ("part_{0:D4}.bin" -f $i)
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $want)) { continue }
    $ok = $false
    for ($try = 1; $try -le 10 -and -not $ok; $try++) {
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        curl.exe -s --fail -L -r "$start-$end" --connect-timeout 30 --max-time 600 -o $dest $url
        if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $want)) { $ok = $true }
        else { Start-Sleep -Seconds 2 }
    }
    if (-not $ok) { "FAILED part $i"; exit 1 }
    "part $i ok ($([math]::Round(($i+1)*100.0/$count,1))%)"
}

"=== concatenating ==="
$fs = [System.IO.File]::Create($out)
foreach ($i in 0..($count - 1)) {
    $f = Join-Path $parts ("part_{0:D4}.bin" -f $i)
    $b = [System.IO.File]::ReadAllBytes($f)
    $fs.Write($b, 0, $b.Length)
}
$fs.Close()
$sz = (Get-Item $out).Length
"size: $sz (expected $total)"
if ($sz -eq $total) {
    $h = (Get-FileHash $out -Algorithm SHA256).Hash
    "sha256: $h"
    if ($h -eq "F2B9147845B4171C55922ED17222CBA6B5D6275076B2C76A3397CDD59F9C8784") {
        "HASH OK - removing parts"
        Remove-Item $parts -Recurse -Force
    } else { "HASH MISMATCH" }
} else { "SIZE MISMATCH" }
