#!/bin/bash
# Run on VPS (e.g. ssh root@89.167.112.246) from /opt/go-flutter-messenger.
# Prereq: DNS pmforu.it.com -> server IP, ports 80 and 443 free.
set -e
DOMAIN=pmforu.it.com
EMAIL="${1:-}"

if [ -z "$EMAIL" ]; then
  echo "Usage: ./infra/setup-https.sh your@email.com"
  exit 1
fi

echo "Stopping containers to free port 80 for certbot..."
docker compose down

echo "Installing certbot if needed..."
apt-get update -qq
apt-get install -y certbot

echo "Getting certificate for $DOMAIN and www.$DOMAIN..."
certbot certonly --standalone -d "$DOMAIN" -d "www.$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --non-interactive

echo "Starting containers..."
docker compose up -d

echo "Done. Test: https://$DOMAIN"
