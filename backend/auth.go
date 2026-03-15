package main

import (
	"crypto/rand"
	"encoding/hex"
	"log"

	"golang.org/x/crypto/bcrypt"
)

const bcryptCost = 10

func hashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

func verifyPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func createSessionToken() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (db *DB) getUserByToken(token string) (*User, error) {
	sess, err := db.GetSessionByToken(token)
	if err != nil {
		return nil, err
	}
	if sess == nil {
		return nil, nil
	}
	u, err := db.GetUserByID(sess.UserID)
	if err != nil {
		log.Printf("GetUserByID: %v", err)
		return nil, err
	}
	return u, nil
}
