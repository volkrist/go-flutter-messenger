# Настройка окружения и запуск

## 1. Flutter в PATH

Если в терминале команда `flutter` не находится:

- Добавь в переменную окружения **PATH** папку с Flutter SDK, например:
  - `C:\src\flutter\bin`
  - или ту, куда ты распаковал Flutter.
- Закрой и заново открой терминал, затем проверь:
  ```bash
  flutter doctor
  ```

## 2. Android лицензии

Если `flutter doctor` просит принять лицензии:

```bash
flutter doctor --android-licenses
```

Несколько раз введи `y`.

## 3. Android SDK

Нужны: Android SDK, Android SDK Platform, Build-Tools, Command-line Tools, Emulator.  
Обычно ставится через **Android Studio** → SDK Manager.

## 4. Устройство для запуска

Проверка доступных устройств:

```bash
flutter devices
```

Варианты: Android emulator, телефон по USB, Windows/Chrome для проверки UI.

## 5. Минимальная последовательность запуска

**Терминал 1 — backend:**

В PowerShell команда `go run .` иногда даёт ошибку `package .cd`. Используй один из вариантов:

```bash
cd C:\Users\Volkr\Desktop\go-flutter-messenger\backend
go run main.go db.go handlers.go types.go websocket.go
```

или скрипты из папки backend: `.\run.bat` или `.\run.ps1`.

Должно появиться: `Server listening on http://localhost:8080`

**Терминал 2 — Flutter:**

```bash
flutter doctor
flutter doctor --android-licenses
cd C:\Users\Volkr\Desktop\go-flutter-messenger\client\flutter_app
flutter pub get
flutter run
```

Если устройств несколько:

```bash
flutter devices
flutter run -d <device_id>
```

## 6. Поддержка Web и запуск в браузере

**Проверить, что Web включён:**

```bash
flutter devices
```

Должны быть строки вроде `Chrome (web)` или `Edge (web)`. Если их нет:

```bash
flutter config --enable-web
flutter devices
```

**Запуск в браузере (сначала запусти backend в отдельном терминале):**

```bash
cd C:\Users\Volkr\Desktop\go-flutter-messenger\client\flutter_app
flutter run -d chrome
```

или:

```bash
flutter run -d edge
```

Flutter соберёт web-версию и откроет приложение по адресу вида `http://localhost:xxxxx`.

**Вариант без автозапуска браузера:**

```bash
flutter run -d web-server
```

Flutter выведет адрес (например `http://localhost:8081`) — открой его вручную в Chrome или Edge.

**Важно:** backend должен быть запущен на `http://localhost:8080` и `ws://localhost:8080/ws`, иначе клиент не подключится.

## 7. Адрес backend в приложении

В проекте настроено автоматически:

- **На ПК (Chrome/Windows):** `http://localhost:8080`, `ws://localhost:8080/ws`
- **В Android-эмуляторе:** `http://10.0.2.2:8080`, `ws://10.0.2.2:8080/ws` (хост берётся из `lib/config.dart`)

На реальном телефоне в той же Wi‑Fi сети нужно подставить IP компьютера (например `192.168.0.15`) — можно вынести в `lib/config.dart` в `backendHost` или задать через переменную окружения при необходимости.

## 8. Частые проблемы

| Проблема | Решение |
|----------|--------|
| `flutter` не найден | Добавить папку `flutter\bin` в PATH |
| Ошибки лицензий Android | `flutter doctor --android-licenses` и везде `y` |
| Нет Android SDK | Установить через Android Studio → SDK Manager |
| Клиент не достучится до backend | Backend должен быть запущен; в эмуляторе используется 10.0.2.2 |
| Нет устройств | Запустить эмулятор или подключить телефон по USB |
