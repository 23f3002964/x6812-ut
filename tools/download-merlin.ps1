$dir = "C:\Users\tanisha\projects\x6812-ut\out\rootfs"
$items = @(
  @{ n = "merlin-device.tar.xz"; u = "https://system-image.ubports.com/pool/device-748f6f225f4081e1bd8b4956b7be851105f1e5ff81a24081959127523c8715c9.tar.xz" },
  @{ n = "merlin-boot.tar.xz";   u = "https://system-image.ubports.com/pool/boot-22a10285e2725b6a95ec96b948b83019d6873841060d985fba6eedf844bbd9fb.tar.xz" }
)
foreach ($it in $items) {
  $o = Join-Path $dir $it.n
  if ((Test-Path $o) -and ((Get-Item $o).Length -gt 1000000)) { "have $($it.n)"; continue }
  "downloading $($it.n) ..."
  for ($t = 1; $t -le 6; $t++) {
    curl.exe -sL --retry 3 --retry-all-errors --connect-timeout 30 --max-time 1800 -o $o $it.u
    if (($LASTEXITCODE -eq 0) -and (Test-Path $o) -and ((Get-Item $o).Length -gt 1000000)) { break }
    Start-Sleep -Seconds 3
  }
  "  size: $((Get-Item $o).Length) bytes"
  "  --- contents ---"
  tar -tf $o 2>$null | ForEach-Object { "  $_" }
}
