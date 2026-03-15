# Проверка FCM и `device_tokens`

## 1. Собрать APK (у себя на ПК)

```powershell
cd c:\Users\Volkr\Desktop\go-flutter-messenger\client\flutter_app
flutter pub get
flutter build apk --release
```

Готовый файл:

`build\app\outputs\flutter-apk\app-release.apk`

## 2. Поставить на устройство

- **Телефон с Google Play** — скопировать APK и установить (разрешить установку из неизвестных источников при необходимости), **или**
- **Эмулятор Android Studio** — образ с иконкой **Play Store** (не «Google APIs» без Play).

На AOSP без GMS `getToken()` часто пустой.

## 3. Запуск с логами

В Cursor / VS Code:

```powershell
cd c:\Users\Volkr\Desktop\go-flutter-messenger\client\flutter_app
flutter run --release
```

Или подключи телефон по USB с отладкой и `flutter run` — в **Debug console** смотри строки:

- `FCM: token зарегистрирован на сервере` — ок;
- `FCM: getToken() empty` — проверь `google-services.json`, package name в Firebase, устройство с Play;
- `FCM: регистрация на сервере не удалась` — смотри текст ошибки (HTTP).

После входа в аккаунт сразу должна пойти регистрация токена.

## 4. Проверка на сервере (SSH как alex)

```bash
docker exec -it go-flutter-messenger-postgres \
  psql -U messenger -d messenger -c "select count(*) from device_tokens;"
```

Если `count > 0` — токен сохранился.

```bash
docker exec -it go-flutter-messenger-postgres \
  psql -U messenger -d messenger -c "select id, username, left(token, 24) || '...' as t, created_at from device_tokens order by id desc limit 5;"
```

## 5. Если всё ещё 0

| Симптом | Действие |
|--------|----------|
| getToken() empty | Firebase + тот же `applicationId`, что в Firebase; образ эмулятора с Play |
| HTTP 401 | JWT не успел сохраниться — редко; перезапуск приложения после логина |
| HTTP 403 | username в теле ≠ пользователю из токена |
| HTTP 500 | логи backend: `docker logs go-flutter-messenger-backend --tail 50` |
