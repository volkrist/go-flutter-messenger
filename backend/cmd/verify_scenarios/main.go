// verify_scenarios runs main API and WS scenarios against a running backend.
// Usage: go run . [baseURL]
// Example: go run . http://localhost:8081
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

func main() {
	base := flag.String("base", "http://localhost:8081", "Base URL of the backend")
	flag.Parse()
	baseURL := strings.TrimSuffix(*base, "/")

	var token1 string
	var roomID int64
	var msgID int64

	ok := func(name string, err error) bool {
		if err != nil {
			fmt.Printf("FAIL %s: %v\n", name, err)
			return false
		}
		fmt.Printf("OK   %s\n", name)
		return true
	}

	suffix := fmt.Sprintf("%d", time.Now().UnixNano()%100000)
	// 1. Register
	u1 := map[string]string{
		"email": "alice_" + suffix + "@test.com", "password": "password123",
		"username": "alice_" + suffix, "displayName": "Alice",
	}
	body, _ := json.Marshal(u1)
	resp, err := http.Post(baseURL+"/auth/register", "application/json", bytes.NewReader(body))
	if !ok("register (alice)", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL register alice: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}
	var auth struct {
		Token string `json:"token"`
		User  struct{ Username string `json:"username"` } `json:"user"`
	}
	json.NewDecoder(resp.Body).Decode(&auth)
	token1 = auth.Token

	u2 := map[string]string{
		"email": "bob_" + suffix + "@test.com", "password": "password123",
		"username": "bob_" + suffix, "displayName": "Bob",
	}
	body, _ = json.Marshal(u2)
	resp, err = http.Post(baseURL+"/auth/register", "application/json", bytes.NewReader(body))
	if !ok("register (bob)", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL register bob: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}
	json.NewDecoder(resp.Body).Decode(&auth)
	_ = auth.Token // bob's token

	// 2. Login
	loginBody := map[string]string{"email": "alice_" + suffix + "@test.com", "password": "password123"}
	body, _ = json.Marshal(loginBody)
	resp, err = http.Post(baseURL+"/auth/login", "application/json", bytes.NewReader(body))
	if !ok("login (alice)", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("FAIL login: status %d\n", resp.StatusCode)
		os.Exit(1)
	}
	json.NewDecoder(resp.Body).Decode(&auth)
	token1 = auth.Token

	// 3. Rooms list
	resp, err = http.Get(baseURL + "/rooms?username=alice_" + suffix)
	if !ok("rooms list", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("FAIL rooms list: status %d\n", resp.StatusCode)
		os.Exit(1)
	}
	var rooms []struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
		Type string `json:"type"`
	}
	json.NewDecoder(resp.Body).Decode(&rooms)

	// 4. Create group room
	groupBody := map[string]string{"name": "Test Group", "creator_username": "alice_" + suffix}
	body, _ = json.Marshal(groupBody)
	resp, err = http.Post(baseURL+"/rooms", "application/json", bytes.NewReader(body))
	if !ok("create group room", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL create group: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}
	var room struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
		Type string `json:"type"`
	}
	json.NewDecoder(resp.Body).Decode(&room)
	roomID = room.ID

	// 5. Create private room (alice with bob)
	privateBody := map[string]string{"current_username": "alice_" + suffix, "target_username": "bob_" + suffix}
	body, _ = json.Marshal(privateBody)
	resp, err = http.Post(baseURL+"/rooms/private", "application/json", bytes.NewReader(body))
	if !ok("create private room", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL create private: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}
	json.NewDecoder(resp.Body).Decode(&room)
	_ = room.ID // private room id

	// 6. Get messages (empty)
	resp, err = http.Get(baseURL + "/messages?roomId=" + fmt.Sprint(roomID) + "&username=alice_" + suffix)
	if !ok("get messages", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("FAIL get messages: status %d\n", resp.StatusCode)
		os.Exit(1)
	}

	// 7. WebSocket: connect, send message, reply, edit, delete, reaction
	wsURL := "ws" + strings.TrimPrefix(baseURL, "http") + "/ws?token=" + url.QueryEscape(token1)
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if !ok("websocket connect", err) {
		os.Exit(1)
	}
	defer conn.Close()

	// send message; read until we get type "message" (ignore presence, etc.)
	sendMsg := func(roomID int64, text string, replyToID *int64) (int64, error) {
		payload := map[string]interface{}{"text": text}
		if replyToID != nil {
			payload["reply_to_id"] = *replyToID
		}
		ev := map[string]interface{}{"type": "message", "roomId": roomID, "payload": payload}
		data, _ := json.Marshal(ev)
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			return 0, err
		}
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			_, raw, err := conn.ReadMessage()
			if err != nil {
				return 0, err
			}
			var out struct {
				Type    string `json:"type"`
				Payload struct {
					ID int64 `json:"id"`
				} `json:"payload"`
			}
			if json.Unmarshal(raw, &out) != nil {
				continue
			}
			if out.Type == "message" && out.Payload.ID > 0 {
				return out.Payload.ID, nil
			}
		}
		return 0, fmt.Errorf("timeout waiting for message response")
	}

	msgID, err = sendMsg(roomID, "Hello world", nil)
	if !ok("send message", err) {
		os.Exit(1)
	}

	replyID, err := sendMsg(roomID, "Reply here", &msgID)
	if !ok("reply", err) {
		os.Exit(1)
	}
	_ = replyID

	// read until expected type
	readUntil := func(wantType string) error {
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			_, raw, err := conn.ReadMessage()
			if err != nil {
				return err
			}
			var out struct {
				Type string `json:"type"`
			}
			if json.Unmarshal(raw, &out) != nil {
				continue
			}
			if out.Type == wantType {
				return nil
			}
		}
		return fmt.Errorf("timeout waiting for %s", wantType)
	}

	// edit message
	editEv := map[string]interface{}{
		"type": "message_edit", "roomId": roomID,
		"payload": map[string]interface{}{"message_id": msgID, "text": "Hello edited"},
	}
	data, _ := json.Marshal(editEv)
	conn.WriteMessage(websocket.TextMessage, data)
	if !ok("edit message", readUntil("message_edited")) {
		os.Exit(1)
	}

	// reaction
	reactionEv := map[string]interface{}{
		"type": "message_reaction", "roomId": roomID,
		"payload": map[string]interface{}{"message_id": msgID, "reaction": "👍"},
	}
	data, _ = json.Marshal(reactionEv)
	conn.WriteMessage(websocket.TextMessage, data)
	if !ok("reaction", readUntil("message_reactions")) {
		os.Exit(1)
	}

	// delete message (we delete reply to keep one message for search)
	deleteEv := map[string]interface{}{
		"type": "message_delete", "roomId": roomID,
		"payload": map[string]interface{}{"message_id": replyID},
	}
	data, _ = json.Marshal(deleteEv)
	conn.WriteMessage(websocket.TextMessage, data)
	if !ok("delete message", readUntil("message_deleted")) {
		os.Exit(1)
	}

	// 8. Search inside chat (Bearer token)
	req, _ := http.NewRequest("GET", baseURL+"/messages/search?room_id="+fmt.Sprint(roomID)+"&q=edited", nil)
	req.Header.Set("Authorization", "Bearer "+token1)
	resp, err = http.DefaultClient.Do(req)
	if !ok("search inside chat", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL search: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}

	// 9. Image upload (multipart with minimal PNG)
	minPNG := []byte{
		0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
		0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
		0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xff, 0xff, 0x3f,
		0x00, 0x05, 0xfe, 0x02, 0xfe, 0xdc, 0xcc, 0x59, 0xe7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
		0x44, 0xae, 0x42, 0x60, 0x82,
	}
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	h := make(textproto.MIMEHeader)
	h.Set("Content-Disposition", `form-data; name="image"; filename="dot.png"`)
	h.Set("Content-Type", "image/png")
	fw, _ := w.CreatePart(h)
	fw.Write(minPNG)
	contentType := w.FormDataContentType()
	w.Close()

	req, _ = http.NewRequest("POST", baseURL+"/upload/image", &buf)
	req.Header.Set("Authorization", "Bearer "+token1)
	req.Header.Set("Content-Type", contentType)
	resp, err = http.DefaultClient.Do(req)
	if !ok("image upload", err) {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		fmt.Printf("FAIL image upload: status %d %s\n", resp.StatusCode, string(b))
		os.Exit(1)
	}
	var imgResp struct {
		ImageURL string `json:"image_url"`
	}
	json.NewDecoder(resp.Body).Decode(&imgResp)
	if imgResp.ImageURL == "" {
		fmt.Printf("FAIL image upload: no image_url in response\n")
		os.Exit(1)
	}

	fmt.Println("\nAll scenarios passed.")
}
