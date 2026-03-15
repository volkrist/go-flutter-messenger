# Copy backend + docker-compose to server. Run from project root. Password: alex.
$ErrorActionPreference = "Stop"
$server = "alex@89.167.112.246"
$remote = "/opt/go-flutter-messenger"
$root = Split-Path $PSScriptRoot -Parent

Write-Host "Copying files to server (one password for all)..."
scp "$root\docker-compose.yml" "${server}:${remote}/"
scp "$root\backend\push.go" "${server}:${remote}/backend/"
scp "$root\backend\main.go" "${server}:${remote}/backend/"
scp "$root\backend\go.mod" "${server}:${remote}/backend/"
if (Test-Path "$root\backend\go.sum") { scp "$root\backend\go.sum" "${server}:${remote}/backend/" }
Write-Host ""
Write-Host "OK. Now open SSH (alex@89.167.112.246) and run this block:"
Write-Host "---"
Write-Host "cd /opt/go-flutter-messenger"
Write-Host "grep FCM .env"
Write-Host "docker compose build --no-cache backend && docker compose up -d backend"
Write-Host "docker logs go-flutter-messenger-backend 2>&1 | head -20"
Write-Host "---"
