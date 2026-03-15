# Push-уведомления (FCM)

Backend использует **путь к JSON-файлу** сервисного аккаунта (`os.ReadFile` в `push.go`), не сырой JSON.

## Что нужно

1. **Firebase Project ID** — из Firebase Console → Project settings.
2. **Service Account JSON** — Firebase Console → Project settings → Service accounts → Generate new private key. Скачать `.json`.

## На сервере

### 1. Папка и файл (обязательно)

Без папки `secrets` и JSON-файла backend **не** выведет "push enabled" и push не заработает.

```bash
mkdir -p /opt/go-flutter-messenger/secrets
```

Положить в неё файл сервисного аккаунта, например:

```bash
# С ПК (из папки, где лежит скачанный JSON):
scp firebase-service-account.json alex@89.167.112.246:/opt/go-flutter-messenger/secrets/
```

Или создать файл на сервере: `nano /opt/go-flutter-messenger/secrets/firebase-service-account.json` и вставить содержимое JSON.

### 2. .env

В `/opt/go-flutter-messenger/.env` добавить или изменить:

```env
FCM_PROJECT_ID=your-firebase-project-id
FCM_SERVICE_ACCOUNT_JSON=/app/secrets/firebase-service-account.json
```

Путь `/app/secrets/...` — **внутри контейнера** backend. В `docker-compose.yml` папка `./secrets` монтируется как `/app/secrets:ro`.

### 3. Имя файла

Если скачанный файл называется иначе (например `my-project-firebase-adminsdk-xxxxx.json`), либо переименуй его в `firebase-service-account.json`, либо укажи в `.env` полное имя:

```env
FCM_SERVICE_ACCOUNT_JSON=/app/secrets/my-project-firebase-adminsdk-xxxxx.json
```

### 4. Перезапуск

```bash
cd /opt/go-flutter-messenger
docker compose up -d --build
docker logs go-flutter-messenger-backend -f
```

В логах не должно быть `push disabled`. Если есть ошибка чтения файла — проверь путь и права (`ls -la secrets/`).

## Проверка

**Токены в БД** (пользователь БД из .env — обычно `messenger`):

```bash
docker exec -it go-flutter-messenger-postgres psql -U messenger -d messenger -c "select id, username, left(token, 24) || '...' as token_preview, created_at from device_tokens order by id desc limit 20;"
```

**Env внутри контейнера:**

```bash
docker exec go-flutter-messenger-backend sh -c 'echo FCM_PROJECT_ID=$FCM_PROJECT_ID && echo FCM_SERVICE_ACCOUNT_JSON=$FCM_SERVICE_ACCOUNT_JSON'
```

**Файл JSON в контейнере:**

```bash
docker exec go-flutter-messenger-backend sh -c 'ls -l /app/secrets && test -f /app/secrets/firebase-service-account.json && echo OK'
```

**Логи по push:**

```bash
docker logs go-flutter-messenger-backend 2>&1 | grep -i push
```

Ожидаемо: `push enabled: Firebase Cloud Messaging initialized`. Не должно быть строк `push disabled`.

- На клиенте: разрешения на уведомления, отправка FCM token на backend после логина.

## Клиент (Flutter)

- `android/app/google-services.json` — из Firebase (package name = `applicationId` в `android/app/build.gradle`).
- После входа/регистрации приложение вызывает `POST /devices/register` с JWT (см. `PushService.registerTokenForUser`).
- **Эмулятор без Google Play** часто не выдаёт FCM token — проверяй на **реальном устройстве** или эмуляторе с образом **Google Play**.
- В **Debug console** при успехе: `FCM: token зарегистрирован на сервере`; при ошибке — текст ответа API или подсказка по `getToken()`.
