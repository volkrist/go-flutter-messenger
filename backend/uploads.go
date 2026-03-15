package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func getUploadsDir() string {
	if d := os.Getenv("UPLOADS_DIR"); d != "" {
		return d
	}
	return "uploads"
}

func handleUploadImage() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		user := userFromContext(r.Context())
		if user == nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		err := r.ParseMultipartForm(10 << 20) // 10 MB
		if err != nil {
			http.Error(w, "failed to parse multipart form", http.StatusBadRequest)
			return
		}

		file, header, err := r.FormFile("image")
		if err != nil {
			http.Error(w, "image is required", http.StatusBadRequest)
			return
		}
		defer file.Close()

		// Определяем тип по содержимому (первые 512 байт)
		buf := make([]byte, 512)
		n, err := file.Read(buf)
		if err != nil && err != io.EOF {
			http.Error(w, "failed to read image", http.StatusBadRequest)
			return
		}

		detectedContentType := http.DetectContentType(buf[:n])

		log.Println("upload filename:", header.Filename)
		log.Println("upload multipart content-type:", header.Header.Get("Content-Type"))
		log.Println("upload detected content-type:", detectedContentType)

		if seeker, ok := file.(io.Seeker); ok {
			_, err = seeker.Seek(0, io.SeekStart)
			if err != nil {
				http.Error(w, "failed to reset file reader", http.StatusInternalServerError)
				return
			}
		} else {
			http.Error(w, "failed to process uploaded image", http.StatusInternalServerError)
			return
		}

		if !strings.HasPrefix(detectedContentType, "image/") {
			http.Error(w, "only image files are allowed", http.StatusBadRequest)
			return
		}

		uploadsDir := getUploadsDir()
		err = os.MkdirAll(uploadsDir, 0755)
		if err != nil {
			http.Error(w, "failed to create uploads dir", http.StatusInternalServerError)
			return
		}

		ext := filepath.Ext(header.Filename)
		if ext == "" {
			switch detectedContentType {
			case "image/jpeg":
				ext = ".jpg"
			case "image/png":
				ext = ".png"
			case "image/gif":
				ext = ".gif"
			case "image/webp":
				ext = ".webp"
			default:
				ext = ".img"
			}
		}

		filename := strings.ReplaceAll(
			time.Now().Format("20060102150405.000000000"),
			".",
			"",
		) + ext

		dstPath := filepath.Join(uploadsDir, filename)

		dst, err := os.Create(dstPath)
		if err != nil {
			http.Error(w, "failed to save image", http.StatusInternalServerError)
			return
		}
		defer dst.Close()

		_, err = io.Copy(dst, file)
		if err != nil {
			http.Error(w, "failed to save image", http.StatusInternalServerError)
			return
		}

		imageURL := "/uploads/" + filename

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"image_url": imageURL,
		})
	}
}
