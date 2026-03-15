package main

// User is the authenticated user (API response).
type User struct {
	ID          int64  `json:"id"`
	Email       string `json:"email"`
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
	Avatar      string `json:"avatar,omitempty"`
}

// Session is stored in DB (not exposed to API).
type Session struct {
	ID        int64
	UserID    int64
	Token     string
	CreatedAt string
	ExpiresAt *string
}

// RegisterRequest is the body of POST /auth/register.
type RegisterRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
}

// LoginRequest is the body of POST /auth/login.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// AuthResponse is the response of register and login.
type AuthResponse struct {
	Token string `json:"token"`
	User  *User  `json:"user"`
}

// MeResponse is the response of GET /me (same shape as User).
type MeResponse struct {
	ID          int64  `json:"id"`
	Email       string `json:"email"`
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
	Avatar      string `json:"avatar,omitempty"`
}

// UpdateMeRequest is the body of PUT /me.
type UpdateMeRequest struct {
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
}

// Message represents a chat message (API and WebSocket payload).
type Message struct {
	ID        int64   `json:"id"`
	Username  string  `json:"username"`
	Text      string  `json:"text"`
	Timestamp string  `json:"timestamp"`
	RoomName  string  `json:"room_name,omitempty"`
	IsRead    bool    `json:"is_read,omitempty"`
	ReplyToID *int64  `json:"reply_to_id,omitempty"`
	ImageURL  *string `json:"image_url,omitempty"`
	EditedAt  *int64  `json:"edited_at,omitempty"`
	DeletedAt *int64  `json:"deleted_at,omitempty"`
}

// WsEvent is the unified WebSocket envelope.
type WsEvent struct {
	Type    string      `json:"type"`
	RoomID  int64       `json:"roomId"`
	Payload interface{} `json:"payload"`
}

// MessagePayload is the payload for type "message".
type MessagePayload struct {
	ID        int64   `json:"id"`
	Username  string  `json:"username"`
	Text      string  `json:"text"`
	Timestamp string  `json:"timestamp"`
	ReplyToID *int64  `json:"reply_to_id,omitempty"`
	ImageURL  *string `json:"image_url,omitempty"`
	EditedAt  *int64  `json:"edited_at,omitempty"`
	DeletedAt *int64  `json:"deleted_at,omitempty"`
}

// PresencePayload is the payload for type "presence".
type PresencePayload struct {
	Users []string `json:"users"`
}

// TypingPayload is the payload for type "typing".
type TypingPayload struct {
	Username string `json:"username"`
	IsTyping bool   `json:"isTyping"`
}

// LastSeenPayload is the payload for type "last_seen".
type LastSeenPayload struct {
	Username string `json:"username"`
	LastSeen string `json:"lastSeen"`
}

// RegisterDeviceTokenRequest is the body of POST /devices/register.
type RegisterDeviceTokenRequest struct {
	Token    string `json:"token"`
	Username string `json:"username"`
	Platform string `json:"platform"`
}
