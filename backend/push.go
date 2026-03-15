package main

import (
	"context"
	"log"
	"os"
	"strconv"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// PushService sends FCM notifications via Firebase Admin SDK.
type PushService struct {
	client *messaging.Client
}

// NewPushService creates PushService from FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT_JSON (path to JSON file).
// Returns nil and logs if push is not configured; does not fail startup.
func NewPushService(ctx context.Context) *PushService {
	projectID := os.Getenv("FCM_PROJECT_ID")
	credsPath := os.Getenv("FCM_SERVICE_ACCOUNT_JSON")

	if projectID == "" {
		log.Println("push disabled: FCM_PROJECT_ID is required")
		return nil
	}
	if credsPath == "" {
		log.Println("push disabled: FCM_SERVICE_ACCOUNT_JSON is required")
		return nil
	}

	if _, err := os.Stat(credsPath); err != nil {
		log.Printf("push disabled: cannot access service account file: %v\n", err)
		return nil
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{
		ProjectID: projectID,
	}, option.WithCredentialsFile(credsPath))
	if err != nil {
		log.Printf("push disabled: firebase init failed: %v\n", err)
		return nil
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("push disabled: firebase messaging init failed: %v\n", err)
		return nil
	}

	log.Println("push enabled: Firebase Cloud Messaging initialized")
	return &PushService{client: client}
}

// SendToToken sends one FCM message to the given token.
func (p *PushService) SendToToken(ctx context.Context, token, title, body string, data map[string]string) error {
	if p == nil || p.client == nil {
		return nil
	}
	if token == "" {
		return nil
	}

	msg := &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
	}

	_, err := p.client.Send(ctx, msg)
	return err
}

// SendMessageNotification sends a chat message notification (used by websocket handler).
func (p *PushService) SendMessageNotification(token string, roomID int64, senderUsername, text string) error {
	if p == nil || p.client == nil {
		return nil
	}
	title := "Новое сообщение от " + senderUsername
	body := text
	if len(body) > 120 {
		body = body[:120] + "..."
	}
	return p.SendToToken(context.Background(), token, title, body, map[string]string{
		"type":            "chat_message",
		"room_id":         strconv.FormatInt(roomID, 10),
		"sender_username": senderUsername,
		"message_text":    text,
	})
}
