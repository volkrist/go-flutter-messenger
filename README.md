# go-flutter-messenger

Production-ready **mobile messenger** built with **Flutter + Go + WebSocket + PostgreSQL**.

This project demonstrates a complete full-stack messaging system with realtime communication, mobile client, backend services, and production infrastructure.

Repository:  
https://github.com/volkrist/go-flutter-messenger

---

# Overview

The project was designed as a **mobile-first MVP messenger** and later evolved into a **production-style architecture** including containerization, reverse proxy, HTTPS, and server deployment.

The system supports realtime messaging, media uploads, chat management, and push notification infrastructure.

---

# Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile Client | Flutter |
| Backend | Go (Golang) |
| Realtime | WebSocket |
| Database | PostgreSQL |
| Infrastructure | Docker, Docker Compose, Nginx, HTTPS (Let's Encrypt), VPS deployment |
| Push Notifications | Firebase Cloud Messaging |

---

# Architecture

```
Flutter Mobile App
        │
        │ HTTPS / WebSocket
        │
        ▼
     Nginx
  Reverse Proxy
        │
        │
        ▼
   Go Backend
 REST API + WS
        │
        │
        ▼
PostgreSQL Database
```

---

# Features

**Authentication**

- User registration
- Login
- Session tokens
- Profile management

**Chats**

- Private chats
- Group chats
- Room membership

**Realtime**

- WebSocket messaging
- Typing indicators
- Presence
- Last seen

**Messages**

- Send messages
- Reply to messages
- Edit messages
- Delete messages

**Reactions**

- Message reactions
- Reaction counters

**Read tracking**

- Read status
- Unread counters

**Media**

- Image upload
- Image messages
- Fullscreen image viewer

**Search**

- Search messages inside chat

**UX**

- Reply preview
- Scroll-to-bottom button
- Date separators
- Chat search

**Push Notifications**

- Firebase Cloud Messaging infrastructure

---

# Mobile Client

Flutter mobile application providing the full messaging interface.

**Implemented screens:**

- Login
- Register
- Chat list
- Chat screen
- User search
- Group management
- Profile
- Settings

**Messaging UI includes:**

- Realtime message updates
- Message reactions
- Image sending
- Reply previews
- Edit / delete messages

---

# Backend

Go backend responsible for messaging logic and realtime communication.

**Core components:**

- REST API
- WebSocket server
- Authentication system
- Session management
- Chat and room management
- Message storage
- Presence tracking
- Push notification integration

---

# Database

PostgreSQL database schema includes:

- users, sessions, rooms, room_members
- messages, message_reads, message_reactions
- device_tokens, user_presence

**Indexes are used for:**

- Message history queries
- Message search
- Room membership lookups
- Reaction queries
- Device token lookup

---

# Infrastructure

The project uses containerized infrastructure.

**Services**

- PostgreSQL database
- Go backend
- Nginx reverse proxy

**Infrastructure capabilities**

- Docker containerization
- Docker Compose orchestration
- HTTPS via Let's Encrypt
- Firewall configuration
- Automatic container restart
- PostgreSQL backup

---

# Project Structure

```
go-flutter-messenger/
├── backend/
│   ├── main.go, db.go, handlers.go, websocket.go
│   ├── auth.go, middleware.go, push.go, uploads.go
│   ├── migrate.go, types.go
│   └── migrations/
│       └── 001_init.sql
├── client/flutter_app/
│   └── lib/
│       ├── models, services, screens, widgets, utils
│       ├── main.dart, config.dart
├── infra/nginx/
│   └── nginx.conf
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

---

# Running Locally

**Requirements**

- Docker, Docker Compose
- Flutter SDK

**Start backend services**

```bash
docker compose up -d --build
```

This will start:

- PostgreSQL
- Go backend
- Nginx reverse proxy

---

# Running Mobile Client

Navigate to the Flutter client:

```
client/flutter_app
```

Install dependencies:

```bash
flutter pub get
```

Run on device or emulator:

```bash
flutter run
```

---

# Production Deployment

The project is deployed on a VPS using Docker Compose.

**Infrastructure includes:**

- Reverse proxy via Nginx
- HTTPS via Let's Encrypt
- Containerized services
- Firewall configuration
- Automated PostgreSQL backups

**External access:**

- https://pmforu.it.com

---

# Development Highlights

- Realtime messaging implemented via WebSocket.
- Backend migrated from SQLite to PostgreSQL with SQL migrations.
- Production infrastructure implemented with: Docker, Docker Compose, Nginx, HTTPS, VPS deployment.
- Push notification infrastructure prepared using Firebase Cloud Messaging.

---

# Author

**Alexander Shvetsov**

Backend Developer  
Python (FastAPI) · Java (Spring Boot)

- GitHub: https://github.com/volkrist
