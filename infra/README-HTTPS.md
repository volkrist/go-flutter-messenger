# HTTPS для pmforu.it.com

## Что уже сделано в репозитории

- **docker-compose.yml**: nginx слушает `80:80` и `443:443`, подключён том `/etc/letsencrypt`.
- **infra/nginx/nginx.conf**: редирект HTTP→HTTPS, один HTTPS server с сертификатами Let's Encrypt для `pmforu.it.com` и `www.pmforu.it.com`.

## Важно: порядок на сервере

Nginx не запустится, пока нет сертификатов. Сначала получаем сертификат с выключенным nginx, потом поднимаем стек.

## Вариант 1: скрипт (рекомендуется)

На сервере, из папки проекта:

```bash
cd /opt/go-flutter-messenger
chmod +x infra/setup-https.sh
./infra/setup-https.sh your@email.com
```

Скрипт: останавливает контейнеры, ставит certbot (если нет), получает сертификат, поднимает контейнеры.

## Вариант 2: вручную

1. Подключиться к серверу:
   ```bash
   ssh root@89.167.112.246
   ```

2. Перейти в проект:
   ```bash
   cd /opt/go-flutter-messenger
   ```

3. Обновить код (если правки были в репо):
   ```bash
   git pull
   ```

4. Установить certbot:
   ```bash
   apt update
   apt install certbot -y
   ```

5. Остановить контейнеры (освободить 80 порт):
   ```bash
   docker compose down
   ```

6. Получить сертификат:
   ```bash
   certbot certonly --standalone -d pmforu.it.com -d www.pmforu.it.com \
     --email YOUR_EMAIL \
     --agree-tos \
     --non-interactive
   ```

7. Запустить стек:
   ```bash
   docker compose up -d
   ```

8. Проверить:
   - https://pmforu.it.com — зелёный замок.
   - http://pmforu.it.com — редирект на https.

## Обновление Flutter-клиента

После перехода на HTTPS в **client/flutter_app/lib/config.dart** заменить адреса на:

```dart
const String backendHttpUrl = 'https://pmforu.it.com';
const String backendWsUrl = 'wss://pmforu.it.com';
```

Пересобрать приложение.

## Продление сертификата

Let's Encrypt выдаёт сертификат на 90 дней. Продление:

```bash
certbot renew
docker compose -f /opt/go-flutter-messenger/docker-compose.yml exec nginx nginx -s reload
```

Или добавить в cron: `0 3 * * * certbot renew --quiet && docker compose -f /opt/go-flutter-messenger/docker-compose.yml exec nginx nginx -s reload`
