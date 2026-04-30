#!/bin/bash
# OpenPaw: Generate image with ComfyUI + send to Discord/LINE
#
# Usage:
#   ./generate-and-send.sh \
#     --prompt "bubu_golden, cheerful golden retriever, sunny morning" \
#     --platform discord \
#     --channel "1495816525590954034" \
#     --caption "早安！汪汪～"
#
# Prerequisites:
#   - ComfyUI running on localhost:8188
#   - DISCORD_BOT_TOKEN or LINE_CHANNEL_ACCESS_TOKEN env var set

set -e

COMFYUI_URL="${COMFYUI_API_URL:-http://localhost:8188}"
PROMPT=""
PLATFORM="discord"
CHANNEL_ID=""
CAPTION=""
LORA_NAME="bubu-golden.safetensors"
LORA_STRENGTH=0.8
WIDTH=1024
HEIGHT=1024
SEED=$RANDOM

while [[ $# -gt 0 ]]; do
  case $1 in
    --prompt) PROMPT="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    --channel) CHANNEL_ID="$2"; shift 2;;
    --caption) CAPTION="$2"; shift 2;;
    --lora) LORA_NAME="$2"; shift 2;;
    --seed) SEED="$2"; shift 2;;
    *) echo "Unknown: $1"; exit 1;;
  esac
done

if [ -z "$PROMPT" ] || [ -z "$CHANNEL_ID" ]; then
  echo "Usage: ./generate-and-send.sh --prompt TEXT --channel ID [--platform discord|line] [--caption TEXT]"
  exit 1
fi

echo "=== OpenPaw Image Generation ==="
echo "Prompt:   $PROMPT"
echo "LoRA:     $LORA_NAME"
echo "Platform: $PLATFORM"
echo "Channel:  $CHANNEL_ID"

# Step 1: Submit to ComfyUI
WORKFLOW=$(cat <<EOF
{
  "prompt": {
    "3": {
      "class_type": "KSampler",
      "inputs": {
        "seed": ${SEED},
        "steps": 4,
        "cfg": 1.0,
        "sampler_name": "euler",
        "scheduler": "simple",
        "denoise": 1.0,
        "model": ["10", 0],
        "positive": ["6", 0],
        "negative": ["7", 0],
        "latent_image": ["5", 0]
      }
    },
    "4": {
      "class_type": "UNETLoader",
      "inputs": {"unet_name": "flux1-schnell.safetensors", "weight_dtype": "default"}
    },
    "5": {
      "class_type": "EmptySD3LatentImage",
      "inputs": {"width": ${WIDTH}, "height": ${HEIGHT}, "batch_size": 1}
    },
    "6": {
      "class_type": "CLIPTextEncode",
      "inputs": {"text": "${PROMPT}", "clip": ["11", 0]}
    },
    "7": {
      "class_type": "CLIPTextEncode",
      "inputs": {"text": "", "clip": ["11", 0]}
    },
    "8": {
      "class_type": "VAEDecode",
      "inputs": {"samples": ["3", 0], "vae": ["9", 0]}
    },
    "9": {
      "class_type": "VAELoader",
      "inputs": {"vae_name": "ae.safetensors"}
    },
    "10": {
      "class_type": "LoraLoader",
      "inputs": {
        "lora_name": "${LORA_NAME}",
        "strength_model": ${LORA_STRENGTH},
        "strength_clip": ${LORA_STRENGTH},
        "model": ["4", 0],
        "clip": ["11", 0]
      }
    },
    "11": {
      "class_type": "DualCLIPLoader",
      "inputs": {
        "clip_name1": "clip_l.safetensors",
        "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
        "type": "flux"
      }
    },
    "12": {
      "class_type": "SaveImage",
      "inputs": {"filename_prefix": "openpaw", "images": ["8", 0]}
    }
  }
}
EOF
)

echo ""
echo "Submitting to ComfyUI..."
RESULT=$(curl -s -X POST "${COMFYUI_URL}/prompt" \
  -H "Content-Type: application/json" \
  -d "$WORKFLOW")

PROMPT_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['prompt_id'])" 2>/dev/null)

if [ -z "$PROMPT_ID" ]; then
  echo "Error: Failed to submit to ComfyUI"
  echo "$RESULT"
  exit 1
fi

echo "Prompt ID: $PROMPT_ID"

# Step 2: Wait for completion
echo "Waiting for generation..."
while true; do
  HISTORY=$(curl -s "${COMFYUI_URL}/history/${PROMPT_ID}")
  STATUS=$(echo "$HISTORY" | python3 -c "
import sys, json
h = json.load(sys.stdin)
if '${PROMPT_ID}' in h:
    outputs = h['${PROMPT_ID}'].get('outputs', {})
    if '12' in outputs:
        imgs = outputs['12'].get('images', [])
        if imgs:
            print(imgs[0]['filename'])
            sys.exit(0)
print('pending')
" 2>/dev/null)

  if [ "$STATUS" != "pending" ] && [ -n "$STATUS" ]; then
    IMAGE_FILE="$STATUS"
    break
  fi
  sleep 1
done

echo "Generated: $IMAGE_FILE"

# Step 3: Download image from ComfyUI
TEMP_IMAGE="/tmp/openpaw-${PROMPT_ID}.png"
curl -s "${COMFYUI_URL}/view?filename=${IMAGE_FILE}" -o "$TEMP_IMAGE"
echo "Downloaded to: $TEMP_IMAGE"

# Step 4: Send to platform
echo ""
echo "Sending to ${PLATFORM}..."

if [ "$PLATFORM" = "discord" ]; then
  if [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo "Error: DISCORD_BOT_TOKEN not set"
    exit 1
  fi

  curl -s -X POST "https://discord.com/api/v10/channels/${CHANNEL_ID}/messages" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -F "content=${CAPTION}" \
    -F "files[0]=@${TEMP_IMAGE}" > /dev/null

  echo "Sent to Discord channel ${CHANNEL_ID}"

elif [ "$PLATFORM" = "line" ]; then
  if [ -z "$LINE_CHANNEL_ACCESS_TOKEN" ]; then
    echo "Error: LINE_CHANNEL_ACCESS_TOKEN not set"
    exit 1
  fi

  # LINE needs a public URL — upload to temp hosting
  # Option 1: Use imgur
  IMAGE_URL=$(curl -s -X POST "https://api.imgur.com/3/image" \
    -H "Authorization: Client-ID ${IMGUR_CLIENT_ID:-openpaw}" \
    -F "image=@${TEMP_IMAGE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['link'])" 2>/dev/null)

  if [ -z "$IMAGE_URL" ]; then
    echo "Warning: Imgur upload failed, sending as text link"
    # Fallback: just mention the image was generated
    curl -s -X POST "https://api.line.me/v2/bot/message/push" \
      -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"to\":\"${CHANNEL_ID}\",\"messages\":[{\"type\":\"text\",\"text\":\"${CAPTION}\n(image generated but upload failed)\"}]}"
  else
    curl -s -X POST "https://api.line.me/v2/bot/message/push" \
      -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"to\":\"${CHANNEL_ID}\",\"messages\":[{\"type\":\"image\",\"originalContentUrl\":\"${IMAGE_URL}\",\"previewImageUrl\":\"${IMAGE_URL}\"},{\"type\":\"text\",\"text\":\"${CAPTION}\"}]}"
    echo "Sent to LINE user ${CHANNEL_ID}"
  fi
fi

# Cleanup
rm -f "$TEMP_IMAGE"
echo ""
echo "Done!"
