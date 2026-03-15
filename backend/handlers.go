package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

func handleWS(hub *Hub, db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			http.Error(w, "token query required", http.StatusBadRequest)
			return
		}
		user, err := db.getUserByToken(token)
		if err != nil {
			log.Printf("getUserByToken: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if user == nil {
			http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
			return
		}
		username := user.Username
		roomIDs, err := db.GetUserRoomIDs(username)
		if err != nil {
			log.Printf("GetUserRoomIDs: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade error: %v", err)
			return
		}
		client := &Client{
			hub:      hub,
			username: username,
			roomIDs:  roomIDs,
			conn:     conn,
			send:     make(chan []byte, 256),
		}
		hub.register <- client
		go client.writePump()
		go client.readPump()
	}
}

func handleRooms(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			username := r.URL.Query().Get("username")
			if username == "" {
				http.Error(w, "username query required", http.StatusBadRequest)
				return
			}
			rooms, err := db.ListRooms(username)
			if err != nil {
				log.Printf("list rooms: %v", err)
				http.Error(w, "Internal error", http.StatusInternalServerError)
				return
			}
			if rooms == nil {
				rooms = []Room{}
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(rooms)
		case http.MethodPost:
			var body struct {
				Name            string `json:"name"`
				CreatorUsername string `json:"creator_username"`
			}

			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, "Invalid JSON", http.StatusBadRequest)
				return
			}

			body.Name = strings.TrimSpace(body.Name)
			body.CreatorUsername = strings.TrimSpace(body.CreatorUsername)

			if body.Name == "" || body.CreatorUsername == "" {
				http.Error(w, "name and creator_username required", http.StatusBadRequest)
				return
			}

			room, err := db.InsertGroupRoom(body.Name, body.CreatorUsername)
			if err != nil {
				log.Printf("insert room: %v", err)
				http.Error(w, "Could not create room", http.StatusInternalServerError)
				return
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(room)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

func handleRoomsPrivate(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var body struct {
			CurrentUsername string `json:"current_username"`
			TargetUsername  string `json:"target_username"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
		if body.CurrentUsername == "" || body.TargetUsername == "" {
			http.Error(w, "current_username and target_username required", http.StatusBadRequest)
			return
		}
		room, err := db.GetOrCreatePrivateRoom(body.CurrentUsername, body.TargetUsername)
		if err != nil {
			log.Printf("get or create private room: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if room == nil {
			http.Error(w, "cannot create chat with yourself", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(room)
	}
}

func handleRoomMembers(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		roomIDStr := strings.TrimSpace(r.URL.Query().Get("roomId"))
		if roomIDStr == "" {
			http.Error(w, "roomId query required", http.StatusBadRequest)
			return
		}

		roomID, err := strconv.ParseInt(roomIDStr, 10, 64)
		if err != nil {
			http.Error(w, "invalid roomId", http.StatusBadRequest)
			return
		}

		exists, err := db.RoomExists(roomID)
		if err != nil {
			log.Printf("room exists check: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if !exists {
			http.Error(w, "room not found", http.StatusNotFound)
			return
		}

		users, err := db.GetRoomMembersDetailed(roomID)
		if err != nil {
			log.Printf("get room members: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if users == nil {
			users = []User{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(users)
	}
}

func handleRoomsRename(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var body struct {
			RoomID int64  `json:"room_id"`
			Name   string `json:"name"`
		}

		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}

		body.Name = strings.TrimSpace(body.Name)
		if body.RoomID <= 0 || body.Name == "" {
			http.Error(w, "room_id and name required", http.StatusBadRequest)
			return
		}

		if err := db.RenameRoom(body.RoomID, body.Name); err != nil {
			log.Printf("rename room: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"room_id": body.RoomID,
			"name":    body.Name,
		})
	}
}

func handleRoomsLeave(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var body struct {
			RoomID   int64  `json:"room_id"`
			Username string `json:"username"`
		}

		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}

		body.Username = strings.TrimSpace(body.Username)
		if body.RoomID <= 0 || body.Username == "" {
			http.Error(w, "room_id and username required", http.StatusBadRequest)
			return
		}

		if err := db.LeaveRoom(body.RoomID, body.Username); err != nil {
			log.Printf("leave room: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"room_id": body.RoomID,
		})
	}
}

func handleRegister(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req RegisterRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
		if req.Email == "" || req.Password == "" || req.Username == "" || req.DisplayName == "" {
			http.Error(w, "email, password, username, displayName required", http.StatusBadRequest)
			return
		}
		if len(req.Password) < 8 {
			http.Error(w, "password must be at least 8 characters", http.StatusBadRequest)
			return
		}
		hash, err := hashPassword(req.Password)
		if err != nil {
			log.Printf("hash password: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		userID, err := db.CreateUser(req.Email, hash, req.Username, req.DisplayName, "")
		if err != nil {
			if strings.Contains(err.Error(), "UNIQUE") {
				http.Error(w, "email or username already taken", http.StatusConflict)
				return
			}
			log.Printf("CreateUser: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		token, err := createSessionToken()
		if err != nil {
			log.Printf("create session token: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if _, err := db.CreateSession(userID, token); err != nil {
			log.Printf("CreateSession: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		user, _ := db.GetUserByID(userID)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(AuthResponse{Token: token, User: user})
	}
}

func handleLogin(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req LoginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
		if req.Email == "" || req.Password == "" {
			http.Error(w, "email and password required", http.StatusBadRequest)
			return
		}
		hash, err := db.GetUserPasswordHash(req.Email)
		if err != nil || hash == "" {
			http.Error(w, "invalid email or password", http.StatusUnauthorized)
			return
		}
		if !verifyPassword(req.Password, hash) {
			http.Error(w, "invalid email or password", http.StatusUnauthorized)
			return
		}
		user, err := db.GetUserByEmail(req.Email)
		if err != nil || user == nil {
			http.Error(w, "invalid email or password", http.StatusUnauthorized)
			return
		}
		token, err := createSessionToken()
		if err != nil {
			log.Printf("create session token: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if _, err := db.CreateSession(user.ID, token); err != nil {
			log.Printf("CreateSession: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(AuthResponse{Token: token, User: user})
	}
}

func handleMe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	user := userFromContext(r.Context())
	if user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(MeResponse{
		ID:          user.ID,
		Email:       user.Email,
		Username:    user.Username,
		DisplayName: user.DisplayName,
		Avatar:      user.Avatar,
	})
}

func handleUpdateMe(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		user := userFromContext(r.Context())
		if user == nil {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		var req UpdateMeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
		req.Username = strings.TrimSpace(req.Username)
		req.DisplayName = strings.TrimSpace(req.DisplayName)
		if req.Username == "" || req.DisplayName == "" {
			http.Error(w, "username and displayName are required", http.StatusBadRequest)
			return
		}
		updatedUser, err := db.UpdateUser(user.ID, req.Username, req.DisplayName)
		if err != nil {
			if strings.Contains(err.Error(), "UNIQUE") {
				http.Error(w, "username already taken", http.StatusConflict)
				return
			}
			log.Printf("UpdateUser: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(updatedUser)
	}
}

func handleMeRoute(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			handleMe(w, r)
		case http.MethodPut:
			handleUpdateMe(db)(w, r)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

func handleRegisterDeviceToken(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		user := userFromContext(r.Context())
		if user == nil {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		var req RegisterDeviceTokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid json body", http.StatusBadRequest)
			return
		}
		req.Username = strings.TrimSpace(req.Username)
		req.Token = strings.TrimSpace(req.Token)
		req.Platform = strings.TrimSpace(req.Platform)
		if req.Username == "" || req.Token == "" {
			http.Error(w, "username and token are required", http.StatusBadRequest)
			return
		}
		if req.Username != user.Username {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		if err := db.SaveDeviceToken(req.Username, req.Token, req.Platform); err != nil {
			log.Printf("SaveDeviceToken: %v", err)
			http.Error(w, "failed to save device token", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": true})
	}
}

func handleGetMessages(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		roomIDStr := r.URL.Query().Get("roomId")
		if roomIDStr == "" {
			http.Error(w, "roomId query required", http.StatusBadRequest)
			return
		}
		username := strings.TrimSpace(r.URL.Query().Get("username"))
		if username == "" {
			http.Error(w, "username query required", http.StatusBadRequest)
			return
		}
		roomID, err := strconv.ParseInt(roomIDStr, 10, 64)
		if err != nil {
			http.Error(w, "invalid roomId", http.StatusBadRequest)
			return
		}
		messages, err := db.GetMessages(roomID, username)
		if err != nil {
			log.Printf("get messages: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if messages == nil {
			messages = []Message{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(messages)
	}
}

func handleMessagesRead(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var body struct {
			RoomID   int64  `json:"room_id"`
			Username string `json:"username"`
		}

		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}

		body.Username = strings.TrimSpace(body.Username)
		if body.RoomID <= 0 || body.Username == "" {
			http.Error(w, "room_id and username required", http.StatusBadRequest)
			return
		}

		if err := db.MarkRoomMessagesRead(body.RoomID, body.Username); err != nil {
			log.Printf("mark read: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}
}

func handleSearchMessages(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		user := userFromContext(r.Context())
		if user == nil {
			http.Error(w, "Authorization required", http.StatusUnauthorized)
			return
		}
		roomIDStr := strings.TrimSpace(r.URL.Query().Get("room_id"))
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		if roomIDStr == "" || q == "" {
			http.Error(w, "room_id and q required", http.StatusBadRequest)
			return
		}
		roomID, err := strconv.ParseInt(roomIDStr, 10, 64)
		if err != nil || roomID <= 0 {
			http.Error(w, "invalid room_id", http.StatusBadRequest)
			return
		}
		inRoom, err := db.IsUserInRoom(roomID, user.Username)
		if err != nil {
			log.Printf("IsUserInRoom: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if !inRoom {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		limitStr := r.URL.Query().Get("limit")
		limit := 50
		if limitStr != "" {
			if n, err := strconv.Atoi(limitStr); err == nil && n > 0 && n <= 100 {
				limit = n
			}
		}
		messages, err := db.SearchMessages(roomID, q, limit)
		if err != nil {
			log.Printf("SearchMessages: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if messages == nil {
			messages = []Message{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(messages)
	}
}

func handleUserSearch(db *DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		query := strings.TrimSpace(r.URL.Query().Get("q"))
		currentUsername := strings.TrimSpace(r.URL.Query().Get("current_username"))

		if query == "" {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode([]User{})
			return
		}

		users, err := db.SearchUsers(query, currentUsername, 20)
		if err != nil {
			log.Printf("search users: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		if users == nil {
			users = []User{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(users)
	}
}
