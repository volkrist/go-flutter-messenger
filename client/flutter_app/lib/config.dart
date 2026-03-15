/// Backend URLs for API and WebSocket (VPS, HTTPS).
/// На реальном телефоне всегда используем production: 127.0.0.1 на устройстве = сам телефон.
/// For local dev on PC: http://localhost:9080, ws://localhost:9080
/// For Android emulator: http://10.0.2.2:9080, ws://10.0.2.2:9080
const String backendHttpUrl = 'https://pmforu.it.com';
const String backendWsUrl = 'wss://pmforu.it.com';
