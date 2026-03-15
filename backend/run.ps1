# Run backend without "go run ." to avoid PowerShell parsing issues (e.g. "package .cd")
Set-Location $PSScriptRoot
go run main.go db.go types.go users.go auth.go middleware.go handlers.go websocket.go
