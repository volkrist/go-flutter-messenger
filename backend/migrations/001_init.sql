CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  avatar TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS rooms (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'group',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS room_members (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  UNIQUE(room_id, username)
);

CREATE TABLE IF NOT EXISTS messages (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  text TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reply_to_id BIGINT,
  image_url TEXT,
  edited_at BIGINT,
  deleted_at BIGINT
);

CREATE TABLE IF NOT EXISTS message_reads (
  id BIGSERIAL PRIMARY KEY,
  message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(message_id, username)
);

CREATE TABLE IF NOT EXISTS device_tokens (
  id BIGSERIAL PRIMARY KEY,
  username TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  platform TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_presence (
  username TEXT PRIMARY KEY,
  last_seen TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS message_reactions (
  id BIGSERIAL PRIMARY KEY,
  message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  reaction TEXT NOT NULL,
  created_at BIGINT NOT NULL,
  UNIQUE(message_id, username, reaction)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_username
  ON device_tokens(username);

CREATE INDEX IF NOT EXISTS idx_sessions_token
  ON sessions(token);

CREATE INDEX IF NOT EXISTS idx_room_members_room_id
  ON room_members(room_id);

CREATE INDEX IF NOT EXISTS idx_room_members_username
  ON room_members(username);

CREATE INDEX IF NOT EXISTS idx_messages_room_id_timestamp
  ON messages(room_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_messages_reply_to_id
  ON messages(reply_to_id);

CREATE INDEX IF NOT EXISTS idx_message_reads_message_id
  ON message_reads(message_id);

CREATE INDEX IF NOT EXISTS idx_message_reads_username
  ON message_reads(username);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id
  ON message_reactions(message_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_username
  ON message_reactions(username);
