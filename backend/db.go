package main

import (
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func openDB() (*sql.DB, error) {
	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}

	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, err
	}

	if err := runMigrations(db, "migrations"); err != nil {
		_ = db.Close()
		return nil, err
	}

	return db, nil
}

// DB wraps the database for handlers.
type DB struct{ *sql.DB }

// Room represents a chat room (list response).
type Room struct {
	ID                   int64  `json:"id"`
	Name                 string `json:"name"`
	Type                 string `json:"type"`
	CreatedAt            string `json:"created_at"`
	LastMessageText      string `json:"last_message_text"`
	LastMessageTimestamp string `json:"last_message_timestamp"`
	OtherUsername        string `json:"other_username,omitempty"`
	UnreadCount          int    `json:"unread_count"`
}

func (db *DB) InsertGroupRoom(name, creatorUsername string) (*Room, error) {
	tx, err := db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var roomID int64
	err = tx.QueryRow(
		`INSERT INTO rooms (name, type, created_at)
		 VALUES ($1, 'group', $2)
		 RETURNING id`,
		name,
		time.Now().UTC(),
	).Scan(&roomID)
	if err != nil {
		return nil, err
	}

	_, err = tx.Exec(
		`INSERT INTO room_members (room_id, username) VALUES ($1, $2)`,
		roomID, creatorUsername,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return db.getRoomByID(roomID, creatorUsername)
}

func (db *DB) GetOrCreatePrivateRoom(currentUsername, targetUsername string) (*Room, error) {
	if currentUsername == targetUsername {
		return nil, nil
	}
	// Find existing private room between these two
	var id int64
	err := db.QueryRow(`
		SELECT r.id FROM rooms r
		WHERE r.type = 'private'
		  AND EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.username = $1)
		  AND EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.username = $2)
		LIMIT 1
	`, currentUsername, targetUsername).Scan(&id)
	if err == nil {
		return db.getRoomByID(id, currentUsername)
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	// Create new private room
	err = db.QueryRow(
		`INSERT INTO rooms (name, type, created_at)
		 VALUES ($1, 'private', $2)
		 RETURNING id`,
		"",
		time.Now().UTC(),
	).Scan(&id)
	if err != nil {
		return nil, err
	}
	_, err = db.Exec(
		`INSERT INTO room_members (room_id, username) VALUES ($1, $2), ($3, $4)`,
		id, currentUsername, id, targetUsername,
	)
	if err != nil {
		return nil, err
	}
	return db.getRoomByID(id, currentUsername)
}

func (db *DB) getRoomByID(id int64, currentUsername string) (*Room, error) {
	var name, roomType, createdAt string
	err := db.QueryRow("SELECT name, type, created_at::text FROM rooms WHERE id = $1", id).Scan(&name, &roomType, &createdAt)
	if err != nil {
		return nil, err
	}
	r := &Room{ID: id, Name: name, Type: roomType, CreatedAt: createdAt, UnreadCount: 0}
	if roomType == "private" {
		var other string
		_ = db.QueryRow("SELECT username FROM room_members WHERE room_id = $1 AND username != $2 LIMIT 1", id, currentUsername).Scan(&other)
		r.OtherUsername = other
		if r.Name == "" {
			r.Name = other
		}
	}
	_ = db.QueryRow(`
		SELECT COALESCE((SELECT text FROM messages WHERE room_id = $1 ORDER BY timestamp DESC LIMIT 1), ''),
		       COALESCE((SELECT timestamp::text FROM messages WHERE room_id = $2 ORDER BY timestamp DESC LIMIT 1), $3)
	`, id, id, createdAt).Scan(&r.LastMessageText, &r.LastMessageTimestamp)
	return r, nil
}

func (db *DB) ListRooms(currentUsername string) ([]Room, error) {
	query := `
		SELECT r.id, r.name, r.type, r.created_at::text,
			COALESCE((SELECT m.text FROM messages m WHERE m.room_id = r.id ORDER BY m.timestamp DESC LIMIT 1), '') AS last_message_text,
			COALESCE((SELECT m.timestamp::text FROM messages m WHERE m.room_id = r.id ORDER BY m.timestamp DESC LIMIT 1), r.created_at::text) AS last_message_timestamp,
			COALESCE((
				SELECT COUNT(*)
				FROM messages m
				WHERE m.room_id = r.id
				  AND m.username != $1
				  AND NOT EXISTS (
				    SELECT 1
				    FROM message_reads mr
				    WHERE mr.message_id = m.id
				      AND mr.username = $2
				  )
			), 0) AS unread_count
		FROM rooms r
		WHERE EXISTS (
			SELECT 1
			FROM room_members rm
			WHERE rm.room_id = r.id AND rm.username = $3
		)
		ORDER BY last_message_timestamp DESC
	`

	rows, err := db.Query(query, currentUsername, currentUsername, currentUsername)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	rooms := make([]Room, 0)
	for rows.Next() {
		var r Room
		if err := rows.Scan(
			&r.ID,
			&r.Name,
			&r.Type,
			&r.CreatedAt,
			&r.LastMessageText,
			&r.LastMessageTimestamp,
			&r.UnreadCount,
		); err != nil {
			return nil, err
		}

		if r.Type == "private" {
			var other string
			_ = db.QueryRow(
				"SELECT username FROM room_members WHERE room_id = $1 AND username != $2 LIMIT 1",
				r.ID,
				currentUsername,
			).Scan(&other)
			r.OtherUsername = other
			if r.Name == "" {
				r.Name = other
			}
		}

		rooms = append(rooms, r)
	}

	return rooms, rows.Err()
}

func (db *DB) InsertMessage(roomID int64, username, text, timestamp string, replyToID *int64, imageURL *string) (int64, error) {
	var id int64
	err := db.QueryRow(`
		INSERT INTO messages (room_id, username, text, timestamp, reply_to_id, image_url)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`, roomID, username, text, timestamp, replyToID, imageURL).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

func (db *DB) MarkRoomMessagesRead(roomID int64, username string) error {
	_, err := db.Exec(`
		INSERT INTO message_reads (message_id, username, read_at)
		SELECT m.id, $1, $2
		FROM messages m
		WHERE m.room_id = $3 AND m.username != $4
		ON CONFLICT (message_id, username) DO NOTHING
	`, username, time.Now().UTC(), roomID, username)
	return err
}

func (db *DB) GetUnreadCount(roomID int64, username string) (int, error) {
	var count int
	err := db.QueryRow(`
		SELECT COUNT(*)
		FROM messages m
		WHERE m.room_id = $1
		  AND m.username != $2
		  AND NOT EXISTS (
		    SELECT 1
		    FROM message_reads mr
		    WHERE mr.message_id = m.id
		      AND mr.username = $3
		  )
	`, roomID, username, username).Scan(&count)
	return count, err
}

func (db *DB) GetMessages(roomID int64, currentUsername string) ([]Message, error) {
	rows, err := db.Query(`
		SELECT
			m.id,
			m.username,
			m.text,
			m.timestamp::text,
			m.reply_to_id,
			m.image_url,
			m.edited_at,
			m.deleted_at,
			CASE
				WHEN m.username = $1 AND EXISTS (
					SELECT 1
					FROM message_reads mr
					WHERE mr.message_id = m.id
				) THEN 1
				ELSE 0
			END AS is_read
		FROM messages m
		WHERE m.room_id = $2
		ORDER BY m.timestamp ASC
	`, currentUsername, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var msg Message
		var replyTo sql.NullInt64
		var imageURL sql.NullString
		var editedAt sql.NullInt64
		var deletedAt sql.NullInt64
		var isReadInt int
		if err := rows.Scan(
			&msg.ID,
			&msg.Username,
			&msg.Text,
			&msg.Timestamp,
			&replyTo,
			&imageURL,
			&editedAt,
			&deletedAt,
			&isReadInt,
		); err != nil {
			return nil, err
		}
		if replyTo.Valid {
			msg.ReplyToID = &replyTo.Int64
		}
		if imageURL.Valid && strings.TrimSpace(imageURL.String) != "" {
			s := imageURL.String
			msg.ImageURL = &s
		}
		if editedAt.Valid && editedAt.Int64 > 0 {
			t := editedAt.Int64
			msg.EditedAt = &t
		}
		if deletedAt.Valid && deletedAt.Int64 > 0 {
			t := deletedAt.Int64
			msg.DeletedAt = &t
		}
		msg.IsRead = isReadInt == 1
		messages = append(messages, msg)
	}
	return messages, rows.Err()
}

// SearchMessages returns messages in the room whose text contains q (case-insensitive), excluding deleted. Order: newest first.
func (db *DB) SearchMessages(roomID int64, q string, limit int) ([]Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	pattern := "%" + q + "%"
	rows, err := db.Query(`
		SELECT m.id, m.username, m.text, m.timestamp::text, m.reply_to_id, m.image_url, m.edited_at, m.deleted_at
		FROM messages m
		WHERE m.room_id = $1 AND m.deleted_at IS NULL AND m.text ILIKE $2
		ORDER BY m.timestamp DESC
		LIMIT $3
	`, roomID, pattern, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var msg Message
		var replyTo sql.NullInt64
		var imageURL sql.NullString
		var editedAt sql.NullInt64
		var deletedAt sql.NullInt64
		if err := rows.Scan(
			&msg.ID,
			&msg.Username,
			&msg.Text,
			&msg.Timestamp,
			&replyTo,
			&imageURL,
			&editedAt,
			&deletedAt,
		); err != nil {
			continue
		}
		if replyTo.Valid {
			msg.ReplyToID = &replyTo.Int64
		}
		if imageURL.Valid && strings.TrimSpace(imageURL.String) != "" {
			s := imageURL.String
			msg.ImageURL = &s
		}
		if editedAt.Valid && editedAt.Int64 > 0 {
			t := editedAt.Int64
			msg.EditedAt = &t
		}
		if deletedAt.Valid && deletedAt.Int64 > 0 {
			t := deletedAt.Int64
			msg.DeletedAt = &t
		}
		msg.IsRead = false
		messages = append(messages, msg)
	}
	return messages, rows.Err()
}

func (db *DB) RoomExists(roomID int64) (bool, error) {
	var n int
	err := db.QueryRow("SELECT 1 FROM rooms WHERE id = $1", roomID).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	return err == nil, err
}

// GetUserRoomIDs returns all room IDs the user is in (membership only).
func (db *DB) GetUserRoomIDs(username string) ([]int64, error) {
	rows, err := db.Query(`
		SELECT r.id FROM rooms r
		WHERE EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.username = $1)
		ORDER BY r.id
	`, username)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// GetRoomMembers returns usernames in the room. For group rooms returns empty (broadcast to all connected with that room in their list is done in Hub).
func (db *DB) GetRoomMembers(roomID int64) ([]string, error) {
	rows, err := db.Query("SELECT username FROM room_members WHERE room_id = $1", roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []string
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

func (db *DB) GetRoomMembersDetailed(roomID int64) ([]User, error) {
	rows, err := db.Query(`
		SELECT u.id, u.email, u.username, u.display_name, COALESCE(u.avatar, '')
		FROM room_members rm
		JOIN users u ON u.username = rm.username
		WHERE rm.room_id = $1
		ORDER BY u.display_name ASC, u.username ASC
	`, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := make([]User, 0)
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.Avatar); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return users, nil
}

func (db *DB) RenameRoom(roomID int64, name string) error {
	_, err := db.Exec(`
		UPDATE rooms
		SET name = $1
		WHERE id = $2 AND type = 'group'
	`, name, roomID)
	return err
}

func (db *DB) LeaveRoom(roomID int64, username string) error {
	_, err := db.Exec(`
		DELETE FROM room_members
		WHERE room_id = $1 AND username = $2
	`, roomID, username)
	return err
}

// IsUserInRoom returns whether the user is in the room (membership only).
func (db *DB) IsUserInRoom(roomID int64, username string) (bool, error) {
	var n int
	err := db.QueryRow("SELECT 1 FROM room_members WHERE room_id = $1 AND username = $2", roomID, username).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	return err == nil, err
}

// SetLastSeen sets last_seen for the user.
func (db *DB) SetLastSeen(username, timestamp string) error {
	_, err := db.Exec(`
		INSERT INTO user_presence (username, last_seen) VALUES ($1, $2)
		ON CONFLICT(username) DO UPDATE SET last_seen = EXCLUDED.last_seen
	`, username, timestamp)
	return err
}

// GetLastSeen returns last_seen for the user, or empty if not set.
func (db *DB) GetLastSeen(username string) (string, error) {
	var lastSeen string
	err := db.QueryRow("SELECT COALESCE(last_seen::text, '') FROM user_presence WHERE username = $1", username).Scan(&lastSeen)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return lastSeen, err
}

// SaveDeviceToken upserts FCM token for the user (by token UNIQUE).
func (db *DB) SaveDeviceToken(username, token, platform string) error {
	if username == "" || token == "" {
		return nil
	}
	_, err := db.Exec(`
		INSERT INTO device_tokens (username, token, platform, created_at, updated_at)
		VALUES ($1, $2, $3, NOW(), NOW())
		ON CONFLICT(token) DO UPDATE SET
			username = EXCLUDED.username,
			platform = EXCLUDED.platform,
			updated_at = NOW()
	`, username, token, platform)
	return err
}

// GetUserDeviceTokens returns all FCM tokens for the user.
func (db *DB) GetUserDeviceTokens(username string) ([]string, error) {
	rows, err := db.Query(`
		SELECT token FROM device_tokens WHERE username = $1
	`, username)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		if t != "" {
			tokens = append(tokens, t)
		}
	}
	return tokens, rows.Err()
}

// GetRoomRecipientTokens returns FCM tokens for all room members except excludeUsername.
func (db *DB) GetRoomRecipientTokens(roomID int64, excludeUsername string) ([]string, error) {
	rows, err := db.Query(`
		SELECT DISTINCT dt.token
		FROM room_members rm
		JOIN device_tokens dt ON dt.username = rm.username
		WHERE rm.room_id = $1 AND rm.username <> $2
	`, roomID, excludeUsername)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		if t != "" {
			tokens = append(tokens, t)
		}
	}
	return tokens, rows.Err()
}
