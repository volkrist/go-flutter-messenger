# go-flutter-messenger

Production-ready mobile messenger built with **Flutter + Go + WebSocket + PostgreSQL**.

A personal real-time messaging project designed as a **full-stack mobile MVP** with production infrastructure.

---

# Architecture

| Layer | Technology |
|-------|------------|
| Mobile Client | Flutter |
| Backend | Go (Golang) |
| Realtime communication | WebSocket |
| Database | PostgreSQL |

**Infrastructure**

- Docker, Docker Compose, Nginx reverse proxy
- HTTPS (Let's Encrypt)
- VPS deployment (Hetzner Cloud)

**Push notifications**

- Firebase Cloud Messaging (FCM)

---

# Features

**Authentication and sessions**

- User registration and login
- Secure session tokens
- Profile editing

**Chat system**

- Private chats
- Group chats
- Room membership

**Realtime messaging**

- WebSocket messaging
- Typing indicators
- Presence / last seen

**Message features**

- Reply to messages
- Edit messages
- Delete messages
- Message reactions
- Read status / unread counters

**Media**

- Image upload
- Image messages
- Fullscreen image viewer

**Search**

- Search messages inside chat

**UX features**

- Scroll to bottom button
- Date separators
- Reply preview
- Chat search

**Push notifications**

- Firebase Cloud Messaging support

---

# Mobile Client

Flutter mobile application with:

- Login / Register
- Chat list
- User search
- Private and group chats
- Realtime messaging UI
- Image sending
- Message reactions
- Edit / delete messages

---

# Backend

Go backend implementing:

- REST API
- WebSocket server

**Core modules**

- users, sessions, rooms, room members
- messages, message reads, message reactions
- device tokens, user presence

---

# Database

PostgreSQL schema includes:

- users, sessions, rooms, room_members
- messages, message_reads, message_reactions
- device_tokens, user_presence

Indexes for performance: message search, room history, device tokens, reactions.

---

# Infrastructure

The project is containerized and deployed using:

- **Docker** + **Docker Compose**

**Services**

- PostgreSQL
- Go backend
- Nginx reverse proxy

**Additional**

- HTTPS via Let's Encrypt
- Firewall configuration (UFW)
- Automatic container restart
- Automated PostgreSQL backups

---

# Project Structure

```
go-flutter-messenger/
├── backend/
├── client/flutter_app/
├── infra/nginx/
├── docker-compose.yml
└── Dockerfile
```

**Backend**

- `backend/main.go`, `db.go`, `handlers.go`, `websocket.go`, `auth.go`, `middleware.go`, `push.go`, `uploads.go`, `migrate.go`, `types.go`
- `backend/migrations/001_init.sql`

**Flutter client**

- `client/flutter_app/lib/` — models, services, screens, widgets, utils

**Infrastructure**

- `infra/nginx/nginx.conf`

---

# Running locally

**Requirements**

- Docker, Docker Compose
- Flutter SDK

**Start backend stack**

```bash
docker compose up -d --build
```

Backend will start with: PostgreSQL, API server, Nginx reverse proxy.

---

# Flutter client

Navigate to:

```
client/flutter_app
```

Install dependencies:

```bash
flutter pub get
```

Run on device:

```bash
flutter run
```

---

# Production deployment

The project is deployed on a VPS with:

- Docker Compose stack
- Nginx reverse proxy
- HTTPS via Let's Encrypt

**External access**

- https://pmforu.it.com

---

# Screenshots

(you can add screenshots of the chat UI here)

---

# Author

**Alexander Shvetsov**

Backend Developer (Python / Java)

- GitHub: https://github.com/volkrist
