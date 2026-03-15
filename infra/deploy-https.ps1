# Copy HTTPS-related files to server, then run setup there.
# Usage: .\infra\deploy-https.ps1 [your@email.com]
# Prereq: SSH key or password for root@89.167.112.246

$ErrorActionPreference = "Stop"
$server = "root@89.167.112.246"
$remote = "/opt/go-flutter-messenger"
$email = $args[0]
if (-not $email) {
    Write-Host "Usage: .\infra\deploy-https.ps1 your@email.com"
    exit 1
}

$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$root\docker-compose.yml")) { $root = (Get-Location).Path }

Write-Host "Copying files to $server..."
Set-Location $root
scp docker-compose.yml "${server}:${remote}/"
scp infra/nginx/nginx.conf "${server}:${remote}/infra/nginx/"
scp infra/setup-https.sh "${server}:${remote}/infra/"

Write-Host "Running setup on server (certbot + restart)..."
ssh $server "cd $remote; chmod +x infra/setup-https.sh; ./infra/setup-https.sh $email"

Write-Host "Done. Open https://pmforu.it.com in browser."
