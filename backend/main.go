package main

import (
	"context"
	"log"
	"net/http"
	"os"
)

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func main() {
	sqlDB, err := openDB()
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer sqlDB.Close()
	db := &DB{sqlDB}

	pushService := NewPushService(context.Background())
	hub := newHub(db, pushService)
	go hub.run()

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if err := db.Ping(); err != nil {
			http.Error(w, "db not ready", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready"))
	})

	http.HandleFunc("/auth/register", handleRegister(db))
	http.HandleFunc("/auth/login", handleLogin(db))
	http.Handle("/me", authMiddleware(db)(http.HandlerFunc(handleMeRoute(db))))
	http.Handle("/devices/register", authMiddleware(db)(http.HandlerFunc(handleRegisterDeviceToken(db))))
	http.Handle("/upload/image", authMiddleware(db)(handleUploadImage()))
	http.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir(getUploadsDir()))))
	http.HandleFunc("/ws", handleWS(hub, db))
	http.HandleFunc("/rooms", handleRooms(db))
	http.HandleFunc("/rooms/private", handleRoomsPrivate(db))
	http.HandleFunc("/rooms/members", handleRoomMembers(db))
	http.HandleFunc("/rooms/rename", handleRoomsRename(db))
	http.HandleFunc("/rooms/leave", handleRoomsLeave(db))
	http.HandleFunc("/messages", handleGetMessages(db))
	http.Handle("/messages/search", authMiddleware(db)(http.HandlerFunc(handleSearchMessages(db))))
	http.HandleFunc("/messages/read", handleMessagesRead(db))
	http.HandleFunc("/users/search", handleUserSearch(db))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port
	log.Println("Server listening on http://localhost" + addr)
	handler := withCORS(http.DefaultServeMux)
	log.Fatal(http.ListenAndServe(addr, handler))
}
