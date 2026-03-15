package main

import (
	"database/sql"
	"strings"
	"time"
)

func (db *DB) CreateUser(email, passwordHash, username, displayName, avatar string) (int64, error) {
	var id int64
	err := db.QueryRow(`
		INSERT INTO users (email, password_hash, username, display_name, avatar, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`,
		email,
		passwordHash,
		username,
		displayName,
		avatar,
		time.Now().UTC(),
	).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

func (db *DB) GetUserByEmail(email string) (*User, error) {
	var u User
	err := db.QueryRow(`
		SELECT id, email, username, display_name, COALESCE(avatar, '')
		FROM users WHERE email = $1
	`, email).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.Avatar)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

func (db *DB) GetUserByID(id int64) (*User, error) {
	var u User
	err := db.QueryRow(`
		SELECT id, email, username, display_name, COALESCE(avatar, '')
		FROM users WHERE id = $1
	`, id).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.Avatar)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

func (db *DB) GetUserPasswordHash(email string) (string, error) {
	var hash string
	err := db.QueryRow("SELECT password_hash FROM users WHERE email = $1", email).Scan(&hash)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", nil
		}
		return "", err
	}
	return hash, nil
}

func (db *DB) CreateSession(userID int64, token string) (int64, error) {
	var id int64
	err := db.QueryRow(`
		INSERT INTO sessions (user_id, token, created_at)
		VALUES ($1, $2, $3)
		RETURNING id
	`, userID, token, time.Now().UTC()).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

func (db *DB) UpdateUser(id int64, username, displayName string) (*User, error) {
	_, err := db.Exec(`
		UPDATE users SET username = $1, display_name = $2 WHERE id = $3
	`, username, displayName, id)
	if err != nil {
		return nil, err
	}
	return db.GetUserByID(id)
}

func (db *DB) GetSessionByToken(token string) (*Session, error) {
	var s Session
	var expiresAt sql.NullString
	err := db.QueryRow(`
		SELECT id, user_id, token, created_at, expires_at FROM sessions WHERE token = $1
	`, token).Scan(&s.ID, &s.UserID, &s.Token, &s.CreatedAt, &expiresAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	if expiresAt.Valid {
		s.ExpiresAt = &expiresAt.String
	}
	return &s, nil
}

func (db *DB) SearchUsers(query, currentUsername string, limit int) ([]User, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return []User{}, nil
	}
	if limit <= 0 {
		limit = 20
	}

	like := "%" + strings.ToLower(query) + "%"

	rows, err := db.Query(`
		SELECT id, email, username, display_name, COALESCE(avatar, '')
		FROM users
		WHERE username != $1
		  AND (
		    LOWER(username) LIKE $2
		    OR LOWER(display_name) LIKE $3
		  )
		ORDER BY
		  CASE
		    WHEN LOWER(username) = LOWER($4) THEN 0
		    WHEN LOWER(display_name) = LOWER($5) THEN 1
		    WHEN LOWER(username) LIKE LOWER($6) THEN 2
		    WHEN LOWER(display_name) LIKE LOWER($7) THEN 3
		    ELSE 4
		  END,
		  username ASC
		LIMIT $8
	`, currentUsername, like, like, query, query, query+"%", query+"%", limit)
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
