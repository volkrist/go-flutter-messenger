# Отчёт проверки Push (автоматически + вручную)

## Проверки, выполненные снаружи (без доступа к серверу и телефону)

| Проверка | Результат |
|----------|-----------|
| `GET https://pmforu.it.com/healthz` | **ok** — HTTP API живой |
| `GET https://pmforu.it.com/readyz` | **ready** — БД на сервере отвечает |
| Цепочка кода push | **Согласована** (см. ниже) |

## Цепочка в коде (проверено по репозиторию)

1. **Клиент** после входа: `PushService.registerTokenForUser` → `POST /devices/register` с JWT.
2. **Backend** `SaveDeviceToken` → таблица `device_tokens`.
3. **Новое сообщение в чате (WebSocket)**: `GetRoomRecipientTokens(roomID, author)` → для каждого токена `SendMessageNotification` (FCM HTTP v1 через Firebase Admin SDK).
4. **Push выключен**, если `pushService == nil` (нет FCM env / файл JSON).

## Что нельзя проверить автоматически с ПК ассистента

- Логи контейнера (`push enabled` / `push send error`)
- `SELECT count(*) FROM device_tokens`
- Доставку уведомления на физическое устройство (FCM + экран телефона)

Без SSH к твоему VPS и без ADB к телефону **подтвердить «пуш реально пришёл» нельзя**.

## Команды для финальной проверки у тебя (2 минуты)

**1. Сервер (SSH):**

```bash
docker logs go-flutter-messenger-backend 2>&1 | grep -i push | tail -5
```

Ожидается строка вида: `push enabled: Firebase Cloud Messaging initialized`

**2. Токены в БД:**

```bash
docker exec go-flutter-messenger-postgres psql -U messenger -d messenger -t -c "select count(*) from device_tokens;"
```

Ожидается **> 0** после входа в приложение на телефоне с Google Play.

**3. Тест push:** второй пользователь пишет в чат первому, у первого приложение **в фоне** — должно прийти уведомление.

---

**Итог:** снаружи подтверждено, что **бэкенд и домен работают**, а **логика push в коде выстроена**. Факт «push работает end-to-end» = **push enabled в логах + count(device_tokens) > 0 + тест сообщения на устройстве**.
