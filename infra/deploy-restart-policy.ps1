# Copy docker-compose.yml to server and restart containers (restart: unless-stopped).
# Run from project root. You will be asked for alex's password.
$ErrorActionPreference = "Stop"
$server = "alex@89.167.112.246"
$remote = "/opt/go-flutter-messenger"
$root = Split-Path $PSScriptRoot -Parent

Write-Host "Copying docker-compose.yml to server..."
scp "$root\docker-compose.yml" "${server}:${remote}/"

Write-Host "Restarting containers on server..."
ssh $server "cd $remote && docker compose down && docker compose up -d && docker ps"

Write-Host "Done."
