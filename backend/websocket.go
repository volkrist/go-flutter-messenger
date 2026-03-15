package main

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Client is a single WebSocket connection per user (one connection for all their rooms).
type Client struct {
	hub           *Hub
	username      string
	roomIDs       []int64
	conn          *websocket.Conn
	send          chan []byte
	closed        bool
	sendCloseOnce sync.Once
}

// Hub keeps one client per username and broadcasts by room.
type Hub struct {
	clients     map[string]*Client
	mu          sync.RWMutex
	register    chan *Client
	unregister  chan *Client
	db          *DB
	pushService *PushService
}

func newHub(db *DB, pushService *PushService) *Hub {
	return &Hub{
		clients:     make(map[string]*Client),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
		db:          db,
		pushService: pushService,
	}
}

func (h *Hub) run() {
	for {
		select {
		case c := <-h.register:
			h.mu.Lock()
			if existing := h.clients[c.username]; existing != nil {
				existing.sendCloseOnce.Do(func() { close(existing.send) })
				delete(h.clients, existing.username)
			}
			h.clients[c.username] = c
			h.mu.Unlock()
			log.Printf("Client connected: %q (rooms: %d)", c.username, len(c.roomIDs))
			h.broadcastPresenceForUserRooms(c.username, c.roomIDs)

		case c := <-h.unregister:
			h.mu.Lock()
			if h.clients[c.username] == c {
				delete(h.clients, c.username)
			}
			c.sendCloseOnce.Do(func() { close(c.send) })
			h.mu.Unlock()
			lastSeen := time.Now().UTC().Format(time.RFC3339)
			if err := h.db.SetLastSeen(c.username, lastSeen); err != nil {
				log.Printf("SetLastSeen: %v", err)
			}
			h.broadcastPresenceForUserRooms(c.username, c.roomIDs)
			h.broadcastLastSeenForUserPrivateRooms(c.username, lastSeen)
		}
	}
}

// BroadcastToRoom sends data to every connected client that has this roomID in their room list.
func (h *Hub) BroadcastToRoom(roomID int64, data []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		if c.closed {
			continue
		}
		for _, id := range c.roomIDs {
			if id == roomID {
				select {
				case c.send <- data:
				default:
					c.closed = true
				}
				break
			}
		}
	}
}

// broadcastPresenceForUserRooms sends updated presence for each of the user's rooms (e.g. after connect/disconnect).
func (h *Hub) broadcastPresenceForUserRooms(username string, roomIDs []int64) {
	for _, roomID := range roomIDs {
		h.broadcastPresence(roomID)
	}
}

// broadcastPresence builds online users for the room (all connected clients that have this room) and sends presence event.
func (h *Hub) broadcastPresence(roomID int64) {
	h.mu.RLock()
	users := make([]string, 0)
	for _, c := range h.clients {
		for _, id := range c.roomIDs {
			if id == roomID {
				users = append(users, c.username)
				break
			}
		}
	}
	h.mu.RUnlock()
	ev := WsEvent{
		Type:   "presence",
		RoomID: roomID,
		Payload: PresencePayload{
			Users: users,
		},
	}
	data, err := json.Marshal(ev)
	if err != nil {
		log.Printf("marshal presence: %v", err)
		return
	}
	h.BroadcastToRoom(roomID, data)
}

// broadcastLastSeenForUserPrivateRooms sends last_seen to the other member of each private room of the user.
func (h *Hub) broadcastLastSeenForUserPrivateRooms(username, lastSeen string) {
	roomIDs, err := h.db.GetUserRoomIDs(username)
	if err != nil {
		return
	}
	for _, roomID := range roomIDs {
		members, err := h.db.GetRoomMembers(roomID)
		if err != nil || len(members) != 2 {
			continue
		}
		var other string
		for _, m := range members {
			if m != username {
				other = m
				break
			}
		}
		if other == "" {
			continue
		}
		ev := WsEvent{
			Type:   "last_seen",
			RoomID: roomID,
			Payload: LastSeenPayload{
				Username: username,
				LastSeen: lastSeen,
			},
		}
		data, err := json.Marshal(ev)
		if err != nil {
			continue
		}
		h.BroadcastToRoom(roomID, data)
	}
}

func (c *Client) hasRoom(roomID int64) bool {
	for _, id := range c.roomIDs {
		if id == roomID {
			return true
		}
	}
	return false
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadLimit(512 * 1024)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("read error: %v", err)
			}
			break
		}
		var envelope WsEvent
		if err := json.Unmarshal(raw, &envelope); err != nil {
			continue
		}
		if envelope.Type != "message_edit" && envelope.Type != "message_delete" && envelope.Type != "message_reaction" {
			if envelope.RoomID == 0 {
				continue
			}
			if !c.hasRoom(envelope.RoomID) {
				continue
			}
		}
		switch envelope.Type {
		case "typing":
			payloadMap, _ := envelope.Payload.(map[string]interface{})
			if payloadMap == nil {
				payloadMap = make(map[string]interface{})
			}
			payloadMap["username"] = c.username
			ev := WsEvent{Type: "typing", RoomID: envelope.RoomID, Payload: payloadMap}
			data, _ := json.Marshal(ev)
			c.hub.BroadcastToRoom(envelope.RoomID, data)
		case "message_edit":
			handleEditMessage(c, envelope)
		case "message_delete":
			handleDeleteMessage(c, envelope)
		case "message_reaction":
			handleReaction(c, envelope)
		case "message":
			payloadMap, _ := envelope.Payload.(map[string]interface{})
			if payloadMap == nil {
				continue
			}
			text, _ := payloadMap["text"].(string)
			var imageURL *string
			if iu, ok := payloadMap["image_url"].(string); ok && iu != "" {
				imageURL = &iu
			}
			if text == "" && imageURL == nil {
				continue
			}
			timestamp := time.Now().UTC().Format(time.RFC3339)
			var replyToID *int64
			if rt, ok := payloadMap["reply_to_id"].(float64); ok && rt > 0 {
				id := int64(rt)
				replyToID = &id
			}
			msgID, err := c.hub.db.InsertMessage(envelope.RoomID, c.username, text, timestamp, replyToID, imageURL)
			if err != nil {
				log.Printf("InsertMessage: %v", err)
				continue
			}
			ev := WsEvent{
				Type:   "message",
				RoomID: envelope.RoomID,
				Payload: MessagePayload{
					ID:        msgID,
					Username:  c.username,
					Text:      text,
					Timestamp: timestamp,
					ReplyToID: replyToID,
					ImageURL:  imageURL,
				},
			}
			data, err := json.Marshal(ev)
			if err != nil {
				continue
			}
			c.hub.BroadcastToRoom(envelope.RoomID, data)
			if c.hub.pushService != nil {
				go func(roomID int64, author, text string) {
					tokens, err := c.hub.db.GetRoomRecipientTokens(roomID, author)
					if err != nil {
						log.Printf("push get tokens error: %v", err)
						return
					}
					for _, token := range tokens {
						if err := c.hub.pushService.SendMessageNotification(token, roomID, author, text); err != nil {
							log.Printf("push send error: %v", err)
						}
					}
				}(envelope.RoomID, c.username, text)
			}
		default:
			// ignore unknown types
		}
	}
}

func handleEditMessage(c *Client, envelope WsEvent) {
	payloadMap, _ := envelope.Payload.(map[string]interface{})
	if payloadMap == nil {
		return
	}
	mid, ok := payloadMap["message_id"]
	if !ok {
		return
	}
	messageID, ok := toInt64(mid)
	if !ok || messageID <= 0 {
		return
	}
	text, _ := payloadMap["text"].(string)

	var authorUsername string
	var roomID int64
	err := c.hub.db.QueryRow(`
		SELECT username, room_id
		FROM messages
		WHERE id = $1
	`, messageID).Scan(&authorUsername, &roomID)
	if err != nil {
		return
	}
	if authorUsername != c.username {
		return
	}
	if !c.hasRoom(roomID) {
		return
	}

	editedAt := time.Now().Unix()
	_, err = c.hub.db.Exec(`
		UPDATE messages
		SET text = $1, edited_at = $2
		WHERE id = $3
	`, text, editedAt, messageID)
	if err != nil {
		log.Printf("UpdateMessage: %v", err)
		return
	}

	ev := WsEvent{
		Type:   "message_edited",
		RoomID: roomID,
		Payload: map[string]interface{}{
			"message_id": messageID,
			"text":       text,
			"edited_at":  editedAt,
		},
	}
	data, err := json.Marshal(ev)
	if err != nil {
		return
	}
	c.hub.BroadcastToRoom(roomID, data)
}

func handleDeleteMessage(c *Client, envelope WsEvent) {
	payloadMap, _ := envelope.Payload.(map[string]interface{})
	if payloadMap == nil {
		return
	}
	mid, ok := payloadMap["message_id"]
	if !ok {
		return
	}
	messageID, ok := toInt64(mid)
	if !ok || messageID <= 0 {
		return
	}

	var authorUsername string
	var roomID int64
	err := c.hub.db.QueryRow(`
		SELECT username, room_id
		FROM messages
		WHERE id = $1
	`, messageID).Scan(&authorUsername, &roomID)
	if err != nil {
		return
	}
	if authorUsername != c.username {
		return
	}
	if !c.hasRoom(roomID) {
		return
	}

	deletedAt := time.Now().Unix()
	_, err = c.hub.db.Exec(`
		UPDATE messages
		SET deleted_at = $1
		WHERE id = $2
	`, deletedAt, messageID)
	if err != nil {
		log.Printf("DeleteMessage: %v", err)
		return
	}

	ev := WsEvent{
		Type:   "message_deleted",
		RoomID: roomID,
		Payload: map[string]interface{}{
			"message_id": messageID,
			"deleted_at": deletedAt,
		},
	}
	data, err := json.Marshal(ev)
	if err != nil {
		return
	}
	c.hub.BroadcastToRoom(roomID, data)
}

func handleReaction(c *Client, envelope WsEvent) {
	payloadMap, _ := envelope.Payload.(map[string]interface{})
	if payloadMap == nil {
		return
	}
	mid, ok := payloadMap["message_id"]
	if !ok {
		return
	}
	messageID, ok := toInt64(mid)
	if !ok || messageID <= 0 {
		return
	}
	reaction, _ := payloadMap["reaction"].(string)
	if reaction == "" {
		return
	}

	var roomID int64
	err := c.hub.db.QueryRow(`SELECT room_id FROM messages WHERE id = $1`, messageID).Scan(&roomID)
	if err != nil {
		return
	}
	if !c.hasRoom(roomID) {
		return
	}

	var exists int
	err = c.hub.db.QueryRow(`
		SELECT 1 FROM message_reactions
		WHERE message_id = $1 AND username = $2 AND reaction = $3
	`, messageID, c.username, reaction).Scan(&exists)
	if err == nil {
		_, _ = c.hub.db.Exec(`
			DELETE FROM message_reactions
			WHERE message_id = $1 AND username = $2 AND reaction = $3
		`, messageID, c.username, reaction)
	} else {
		_, _ = c.hub.db.Exec(`
			INSERT INTO message_reactions (message_id, username, reaction, created_at)
			VALUES ($1, $2, $3, $4)
		`, messageID, c.username, reaction, time.Now().Unix())
	}

	rows, err := c.hub.db.Query(`
		SELECT reaction, COUNT(*)
		FROM message_reactions
		WHERE message_id = $1
		GROUP BY reaction
	`, messageID)
	if err != nil {
		return
	}
	defer rows.Close()

	reactions := map[string]int{}
	for rows.Next() {
		var r string
		var cnt int
		if err := rows.Scan(&r, &cnt); err != nil {
			continue
		}
		reactions[r] = cnt
	}

	ev := WsEvent{
		Type:   "message_reactions",
		RoomID: roomID,
		Payload: map[string]interface{}{
			"message_id": messageID,
			"reactions":  reactions,
		},
	}
	data, err := json.Marshal(ev)
	if err != nil {
		return
	}
	c.hub.BroadcastToRoom(roomID, data)
}

func toInt64(v interface{}) (int64, bool) {
	switch n := v.(type) {
	case float64:
		return int64(n), true
	case int:
		return int64(n), true
	case int64:
		return n, true
	default:
		return 0, false
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
