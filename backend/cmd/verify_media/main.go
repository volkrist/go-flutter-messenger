// verify_media runs the 4 media checks from MEDIA_VERIFICATION.md.
// Usage: go run ./cmd/verify_media [baseURL]
// Default baseURL: http://localhost:8081
// Backend must be running (e.g. PORT=8081 go run .).
package main

import (
	"bytes"
	"encoding/json"
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
	base := "http://localhost:8081"
	if len(os.Args) > 1 {
		base = strings.TrimSuffix(os.Args[1], "/")
	}
	baseURL, _ := url.Parse(base)
	wsScheme := "ws"
	if baseURL.Scheme == "https" {
		wsScheme = "wss"
	}
	wsHost := baseURL.Host

	ok := true

	// 1. Upload without token -> 401
	fmt.Println("Check 1: POST /upload/image without token -> 401")
	resp, err := http.Post(base+"/upload/image", "application/octet-stream", nil)
	if err != nil {
		fmt.Printf("  FAIL: %v\n", err)
		ok = false
	} else {
		resp.Body.Close()
		if resp.StatusCode != 401 {
			fmt.Printf("  FAIL: got %d, want 401\n", resp.StatusCode)
			ok = false
		} else {
			fmt.Println("  OK")
		}
	}

	// 2. Register, login, upload with token -> 200, image_url
	fmt.Println("Check 2: Upload with token -> 200, image_url")
	regBody := `{"email":"verify_media@test.local","password":"password123","username":"verify_media","displayName":"Verify"}`
	resp, err = http.Post(base+"/auth/register", "application/json", strings.NewReader(regBody))
	if err != nil {
		fmt.Printf("  FAIL register: %v\n", err)
		ok = false
	} else {
		resp.Body.Close()
		// ignore if already exists
	}
	loginBody := `{"email":"verify_media@test.local","password":"password123"}`
	resp, err = http.Post(base+"/auth/login", "application/json", strings.NewReader(loginBody))
	if err != nil {
		fmt.Printf("  FAIL login: %v\n", err)
		ok = false
	} else {
		var loginResp struct {
			Token string `json:"token"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&loginResp)
		resp.Body.Close()
		token := loginResp.Token
		if token == "" {
			fmt.Println("  FAIL: no token in login response")
			ok = false
		} else {
			// Create minimal 1x1 PNG and upload
			pngBytes := []byte{
				0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
				0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
				0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
				0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
				0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
				0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
				0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
				0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
				0x42, 0x60, 0x82,
			}
			var buf bytes.Buffer
			w := multipart.NewWriter(&buf)
			h := textproto.MIMEHeader{}
			h.Set("Content-Disposition", `form-data; name="image"; filename="test.png"`)
			h.Set("Content-Type", "image/png")
			fw, _ := w.CreatePart(h)
			fw.Write(pngBytes)
			contentType := w.FormDataContentType()
			w.Close()
			req, _ := http.NewRequest("POST", base+"/upload/image", &buf)
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", contentType)
			resp, err = http.DefaultClient.Do(req)
			if err != nil {
				fmt.Printf("  FAIL upload: %v\n", err)
				ok = false
			} else {
				body, _ := io.ReadAll(resp.Body)
				resp.Body.Close()
				if resp.StatusCode != 200 {
					fmt.Printf("  FAIL: got %d, body: %s\n", resp.StatusCode, body)
					ok = false
				} else {
					var uploadResp struct {
						ImageURL string `json:"image_url"`
					}
					if json.Unmarshal(body, &uploadResp) != nil || uploadResp.ImageURL == "" {
						fmt.Printf("  FAIL: no image_url in response: %s\n", body)
						ok = false
					} else {
						fmt.Printf("  OK (image_url: %s)\n", uploadResp.ImageURL)
					}
				}
			}
		}
	}

	// 3 & 4: WS send message with only image; then image + text; verify via GET /messages
	fmt.Println("Check 3 & 4: Send image-only and image+text via WS; verify in /messages")
	loginBody = `{"email":"verify_media@test.local","password":"password123"}`
	resp, err = http.Post(base+"/auth/login", "application/json", strings.NewReader(loginBody))
	if err != nil {
		fmt.Printf("  FAIL login: %v\n", err)
		ok = false
	} else {
		var loginResp struct {
			Token string `json:"token"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&loginResp)
		resp.Body.Close()
		token := loginResp.Token
		if token == "" {
			fmt.Println("  FAIL: no token")
			ok = false
		} else {
			// Get or create room
			resp, err = http.Get(base + "/rooms?username=verify_media")
			if err != nil {
				fmt.Printf("  FAIL get rooms: %v\n", err)
				ok = false
			} else {
				var rooms []struct {
					ID   int64  `json:"id"`
					Name string `json:"name"`
				}
				_ = json.NewDecoder(resp.Body).Decode(&rooms)
				resp.Body.Close()
				var roomID int64
				if len(rooms) > 0 {
					roomID = rooms[0].ID
				} else {
					createBody := `{"name":"Verify Media Room","creator_username":"verify_media"}`
					resp, err = http.Post(base+"/rooms", "application/json", strings.NewReader(createBody))
					if err != nil {
						fmt.Printf("  FAIL create room: %v\n", err)
						ok = false
					} else {
						var room struct {
							ID int64 `json:"id"`
						}
						_ = json.NewDecoder(resp.Body).Decode(&room)
						resp.Body.Close()
						roomID = room.ID
					}
				}
				if roomID != 0 {
					wsURL := fmt.Sprintf("%s://%s/ws?token=%s", wsScheme, wsHost, url.QueryEscape(token))
					conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
					if err != nil {
						fmt.Printf("  FAIL WS connect: %v\n", err)
						ok = false
					} else {
						defer conn.Close()
						imageURL := base + "/uploads/test_1x1.png"
						// Message 1: only image
						msg1 := map[string]any{
							"type":    "message",
							"roomId": roomID,
							"payload": map[string]any{"image_url": imageURL},
						}
						b1, _ := json.Marshal(msg1)
						if err := conn.WriteMessage(websocket.TextMessage, b1); err != nil {
							fmt.Printf("  FAIL send image-only: %v\n", err)
							ok = false
						} else {
							// Message 2: image + text
							msg2 := map[string]any{
								"type":    "message",
								"roomId": roomID,
								"payload": map[string]any{"image_url": imageURL, "text": "Check 4: image + text"},
							}
							b2, _ := json.Marshal(msg2)
							if err := conn.WriteMessage(websocket.TextMessage, b2); err != nil {
								fmt.Printf("  FAIL send image+text: %v\n", err)
								ok = false
							} else {
								time.Sleep(300 * time.Millisecond)
								// Verify via GET /messages
								resp, err = http.Get(fmt.Sprintf("%s/messages?roomId=%d&username=verify_media", base, roomID))
								if err != nil {
									fmt.Printf("  FAIL get messages: %v\n", err)
									ok = false
								} else {
									body, _ := io.ReadAll(resp.Body)
									resp.Body.Close()
									var messages []struct {
										Text     string  `json:"text"`
										ImageURL *string `json:"image_url"`
									}
									if json.Unmarshal(body, &messages) != nil {
										fmt.Printf("  FAIL parse messages: %s\n", body)
										ok = false
									} else {
										var hasImageOnly, hasImageAndText bool
										for _, m := range messages {
											if m.ImageURL != nil && *m.ImageURL != "" {
												if m.Text == "" {
													hasImageOnly = true
												} else if strings.Contains(m.Text, "Check 4") {
													hasImageAndText = true
												}
											}
										}
										if !hasImageOnly {
											fmt.Println("  FAIL: no message with only image")
											ok = false
										} else if !hasImageAndText {
											fmt.Println("  FAIL: no message with image + text")
											ok = false
										} else {
											fmt.Println("  OK (image-only and image+text messages found)")
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	if !ok {
		os.Exit(1)
	}
	fmt.Println("\nAll 4 checks passed.")
}
