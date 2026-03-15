@echo off
cd /d "%~dp0"
go run main.go db.go types.go users.go auth.go middleware.go handlers.go websocket.go
