# Sending Images from Agent to Chat Platform

OpenAB is text-only by design — the `ChatAdapter` trait sends `&str`, not binary data.
This document describes best practices for agents to send images back to users **without modifying OpenAB core**.

## Overview

```
Agent generates image → saves to filesystem
                              ↓
              Option A: Agent sends directly via platform API
              Option B: Sidecar watches folder and uploads
```

---

## Option A: Agent Sends Directly (Recommended)

The agent (Claude Code, Codex, etc.) can call platform APIs directly using available tools (Bash, WebFetch, etc.) to upload images to the originating conversation.

### Prerequisites

The agent needs:
1. **Platform Bot Token** — available via environment variable
2. **Thread/Channel ID** — available in `sender_context` injected by OpenAB
3. **Image file** — generated locally by the agent

### Discord

```bash
# Upload image as attachment to Discord thread
curl -X POST "https://discord.com/api/v10/channels/${THREAD_ID}/messages" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -F "content=Here's the image you requested!" \
  -F "files[0]=@/path/to/generated-image.png"
```

The agent can extract `channel_id` from the `sender_context` that OpenAB injects into every message:
```json
{
  "sender_id": "729900334809350144",
  "sender_name": "username",
  "channel": "discord",
  "channel_id": "1495816525590954034"
}
```

### LINE

LINE requires a **public URL** for images (does not accept file uploads directly).

```bash
# Step 1: Upload image to get a public URL
# Option: Upload to S3, Imgur, or any file hosting
IMAGE_URL=$(upload_to_hosting /path/to/image.png)

# Step 2: Send image message via LINE Push API
curl -X POST "https://api.line.me/v2/bot/message/push" \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "'${USER_ID}'",
    "messages": [{
      "type": "image",
      "originalContentUrl": "'${IMAGE_URL}'",
      "previewImageUrl": "'${IMAGE_URL}'"
    }]
  }'
```

### Telegram

```bash
# Upload image directly via Telegram Bot API
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
  -F "chat_id=${CHAT_ID}" \
  -F "photo=@/path/to/generated-image.png" \
  -F "caption=Here's the image!"
```

---

## Option B: Sidecar File Watcher

A separate process watches a directory for new images and uploads them to the correct conversation thread.

### Architecture

```
Agent (Claude/Codex/etc.)
  │
  ├── Generates image → /path/to/generated_images/{session_id}/image.png
  │
  └── Responds with text → OpenAB → Platform (text only)

image-uploader (sidecar)
  │
  ├── Watches /path/to/generated_images/
  ├── Detects new image file
  ├── Reads session metadata to find thread_id + platform
  ├── Uploads to correct platform via API
  └── Marks as uploaded (state file to avoid duplicates)
```

### Example: discord-image-uploader

```bash
#!/bin/bash
# Simple file watcher for Discord image upload
# Watches a directory and uploads new images to Discord

WATCH_DIR="/home/node/.codex/generated_images"
STATE_FILE="/home/node/.codex/discord-image-uploader-state.txt"
BOT_TOKEN="${DISCORD_BOT_TOKEN}"

touch "$STATE_FILE"

inotifywait -m -r -e create "$WATCH_DIR" | while read dir event file; do
  filepath="${dir}${file}"
  
  # Skip if already uploaded
  grep -qF "$filepath" "$STATE_FILE" && continue
  
  # Extract session_id from directory path
  session_id=$(basename "$dir")
  
  # Read sender_context from session to get thread_id
  thread_id=$(jq -r '.channel_id' "/path/to/sessions/${session_id}/context.json")
  
  # Upload to Discord
  curl -X POST "https://discord.com/api/v10/channels/${thread_id}/messages" \
    -H "Authorization: Bot ${BOT_TOKEN}" \
    -F "files[0]=@${filepath}"
  
  # Mark as uploaded
  echo "$filepath" >> "$STATE_FILE"
done
```

---

## Image Generation Methods

Agents can generate images using various methods:

| Method | Provider | Cost | Quality | Setup |
|--------|----------|------|---------|-------|
| Codex `imagegen` | OpenAI (built-in) | API cost | High | Zero (built-in) |
| Zeabur AI Hub | Gemini 2.5 Flash Image | API cost | High | Zeabur CLI login |
| ComfyUI + Flux.1 | Local GPU | Free | High | GPU + ComfyUI setup |
| ComfyUI + SDXL | Local GPU | Free | Good | GPU + ComfyUI setup |
| Claude SVG | Anthropic | Included | Basic | Zero |

### Local GPU (ComfyUI API)

```bash
# Generate image via ComfyUI REST API
curl -X POST "http://localhost:8188/prompt" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": {
      "3": {
        "class_type": "KSampler",
        "inputs": {
          "seed": 42,
          "steps": 4,
          "cfg": 1.0,
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1.0,
          "model": ["4", 0],
          "positive": ["6", 0],
          "negative": ["7", 0],
          "latent_image": ["5", 0]
        }
      }
    }
  }'
```

---

## Security Considerations

1. **Bot Token exposure** — pass tokens via environment variables, never hardcode
2. **File path traversal** — validate image paths before uploading
3. **Rate limiting** — platform APIs have rate limits (Discord: 5 msg/5s per channel)
4. **Image size** — Discord max 25MB, LINE max 10MB, Telegram max 10MB
5. **Content moderation** — consider filtering generated content before sending

---

## Environment Variables

```bash
# Discord
DISCORD_BOT_TOKEN=your-bot-token

# LINE
LINE_CHANNEL_ACCESS_TOKEN=your-access-token

# Telegram
TELEGRAM_BOT_TOKEN=your-bot-token

# ComfyUI (local)
COMFYUI_API_URL=http://localhost:8188
```
