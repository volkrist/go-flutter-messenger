# go-flutter-messenger

A simple realtime messenger MVP: Go backend with WebSockets and SQLite, Flutter client with a familiar chat UX.

## Features

- **Login** by username
- **Chat list** — group and private (1-to-1) chats, create group or private chat
- **Chat room** — message history, realtime updates, bubbles, presence, typing indicator
- **Backend:** Go, `net/http`, gorilla/websocket, SQLite
- **Storage:** rooms (type: group/private), room_members, messages by room_id
- **Realtime:** WebSocket per room (by roomId); presence and typing events

## Project structure

```
go-flutter-messenger/
├── backend/
│   ├── main.go        # server, routes, DB init
│   ├── db.go          # SQLite: rooms, messages
│   ├── types.go       # Message, Room
│   ├── websocket.go   # room-scoped hub
│   ├── handlers.go   # REST + WebSocket handlers
│   └── go.mod
├── client/flutter_app/
│   └── lib/
│       ├── main.dart
│       ├── models/      # message, room
│       ├── screens/     # login, chat_list, chat
│       ├── services/    # api_service, chat_service
│       └── widgets/     # message_bubble, chat_input, empty_chats
└── README.md
```

## Backend

**Database (SQLite, file `messenger.db` in `backend/`):**
- `rooms` — id, name, type (group/private), created_at
- `room_members` — id, room_id, username (for private rooms)
- `messages` — id, room_id, username, text, timestamp

**Endpoints:**
- `GET /rooms?username=<name>` — list group rooms + private rooms for that user; includes last_message_*, sorted by activity
- `POST /rooms` — create group room (body: `{"name": "Room Name"}`)
- `POST /rooms/private` — get or create private room (body: `{"current_username": "Alex", "target_username": "Bob"}`)
- `GET /messages?roomId=<id>` — message history for the room
- `ws://localhost:8080/ws?roomId=<id>&username=<name>` — WebSocket for realtime chat

**Behaviour:** Messages stored in SQLite; broadcast and presence/typing only within the same room.

### Run backend

Need **Go** and a C toolchain (for SQLite; on Windows e.g. MinGW/gcc).

```bash
cd backend
go get github.com/mattn/go-sqlite3
go run .
```

Server runs at **http://localhost:8080**. A default room `general` is created on first start. You can create more (e.g. Work, Friends, Ideas) from the app.

## Flutter app

**Screens:**
1. **Login** — app title, username field, Continue
2. **Chats** — list of group + private chats; FABs: new group chat, new private chat (enter username); tap to open
3. **Chat** — app bar with room/contact name, online status, message list, typing indicator, input + send

**UI:** Messenger-style layout, rounded bubbles, clear spacing, loading and empty states.

### Run Flutter app

Need **Flutter** in `PATH`.

```bash
cd client/flutter_app
flutter pub get
flutter run
```

Select a device (Chrome, Windows, etc.). Start the backend first.

## Quick test

1. **Backend:** `cd backend && go get github.com/mattn/go-sqlite3 && go run .`
2. **Flutter:** `cd client/flutter_app && flutter pub get && flutter run`
3. Enter username → Continue → open a chat (e.g. General) or create one (Work, Friends, …) → send messages.
4. Open another client; history loads, new messages appear in realtime in the same room.
