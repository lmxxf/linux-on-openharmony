# Linux on OpenHarmony - Windows one-click deploy
# Usage: .\deploy.ps1
# Requires: hdc connected to device

$ErrorActionPreference = "Stop"

Write-Host "[*] Checking device ..." -ForegroundColor Cyan
$targets = hdc list targets 2>&1
if ($targets -match "Empty" -or $LASTEXITCODE -ne 0) {
    Write-Host "[!] No device found" -ForegroundColor Red
    exit 1
}
Write-Host "[*] Device: $targets" -ForegroundColor Green

Write-Host "[*] Pushing files ..." -ForegroundColor Cyan
hdc file send install.sh /data/local/tmp/install.sh
hdc file send setup-desktop.sh /data/local/tmp/setup-desktop.sh
hdc file send alpine-minirootfs-3.21.3-aarch64.tar.gz /data/local/tmp/alpine-minirootfs.tar.gz

Write-Host "[*] Installing Alpine ..." -ForegroundColor Cyan
hdc shell "sh /data/local/tmp/install.sh"

# Copy setup script into Alpine rootfs so chroot can see it
hdc shell "cp /data/local/tmp/setup-desktop.sh /data/alpine/tmp/setup-desktop.sh"

Write-Host "[*] Setting up desktop environment ..." -ForegroundColor Cyan
hdc shell "chroot /data/alpine /bin/sh -c 'export PATH=/usr/bin:/usr/sbin:/bin:/sbin; sh /tmp/setup-desktop.sh'"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Deploy complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Set root password:" -ForegroundColor Yellow
Write-Host "       hdc shell"
Write-Host "       sh /data/local/tmp/alpine-enter.sh"
Write-Host "       passwd root"
Write-Host ""
Write-Host "    2. Start services:" -ForegroundColor Yellow
Write-Host "       sh ~/start-services.sh 1920x1080"
Write-Host ""
Write-Host "    3. SSH (via hdc port forward):" -ForegroundColor Yellow
Write-Host "       hdc fport tcp:2222 tcp:22"
Write-Host "       ssh root@127.0.0.1 -p 2222"
Write-Host ""
Write-Host "    4. VNC:" -ForegroundColor Yellow
Write-Host "       Connect VNC client to <device-IP>:5900"
Write-Host "========================================" -ForegroundColor Green
