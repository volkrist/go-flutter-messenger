# syntax=docker/dockerfile:1
FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata

COPY backend/go.mod backend/go.sum ./backend/
WORKDIR /app/backend
RUN go mod download

COPY backend/ ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/bin/messenger-backend .

FROM alpine:3.22

WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata wget

COPY --from=builder /app/bin/messenger-backend /app/messenger-backend
COPY --from=builder /app/backend/migrations /app/migrations

ENV PORT=8080

EXPOSE 8080

CMD ["/app/messenger-backend"]
