# Push Notifications — настройка и проверка

## Backend (Go)

1. **Переменные окружения для FCM**
   - `FIREBASE_PROJECT_ID` — ID проекта в Firebase Console.
   - `GOOGLE_APPLICATION_CREDENTIALS` — путь к JSON ключу сервисного аккаунта (Firebase Console → Project settings → Service accounts → Generate new private key).

   Без этих переменных push не отправляется (логируется предупреждение).

2. **Запуск**
   ```bash
   cd backend
   set FIREBASE_PROJECT_ID=your-project-id
   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
   go run .
   ```

## Flutter

1. **Firebase**
   - В [Firebase Console](https://console.firebase.google.com) создайте проект и добавьте Android-приложение (package: `com.example.flutter_app`).
   - Скачайте `google-services.json` и положите в `client/flutter_app/android/app/` (замените текущий placeholder).
   - Выполните: `dart run flutterfire_cli configure` в `client/flutter_app` — подставит реальные значения в `lib/firebase_options.dart` (или вручную заполните `lib/firebase_options.dart` и `android/app/google-services.json`).

2. **Сборка и запуск**
   ```bash
   cd client/flutter_app
   flutter pub get
   flutter run
   ```

## Проверка

1. Запустите backend с заданными env.
2. Запустите приложение, войдите под пользователем A.
3. На другом устройстве/эмуляторе войдите под пользователем B (или откройте второй клиент).
4. Добавьте B в общую комнату с A (или создайте личный чат A–B).
5. От пользователя A отправьте сообщение в комнату.
6. У пользователя B должно прийти push (в foreground — локальное уведомление, в background/закрытом приложении — системное от FCM).
7. Тап по уведомлению открывает экран чата этой комнаты.

## Файлы изменений

**Backend:** `db.go` (таблица `device_tokens`, `SaveDeviceToken`, `GetDeviceTokensForUsernames`), `fcm.go` (новый), `handlers.go` (`handleDevicesRegister`), `main.go` (роут `/devices/register`), `websocket.go` (вызов push после отправки сообщения).

**Flutter:** `pubspec.yaml`, `lib/main.dart`, `lib/firebase_options.dart`, `lib/services/push_service.dart`, `lib/screens/chat_list_screen.dart`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `android/app/google-services.json`.
