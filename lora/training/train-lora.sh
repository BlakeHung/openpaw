#!/bin/bash
# OpenPaw LoRA Training Script
# Train a LoRA on pet/mascot photos for Flux.1-schnell
#
# Prerequisites:
#   pip install ai-toolkit  (or kohya-ss/sd-scripts)
#   15-20 photos of your pet (various angles/expressions/scenes)
#
# Usage:
#   ./train-lora.sh --images /path/to/photos --output bubu-golden.safetensors

set -e

# Defaults
IMAGES_DIR=""
OUTPUT_FILE=""
TRIGGER_WORD="bubu_golden"
RESOLUTION=512
STEPS=1500
LR=1e-4
RANK=16
BATCH_SIZE=1

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --images) IMAGES_DIR="$2"; shift 2;;
    --output) OUTPUT_FILE="$2"; shift 2;;
    --trigger) TRIGGER_WORD="$2"; shift 2;;
    --steps) STEPS="$2"; shift 2;;
    --rank) RANK="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [ -z "$IMAGES_DIR" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: ./train-lora.sh --images /path/to/photos --output name.safetensors"
  echo ""
  echo "Options:"
  echo "  --images    Directory containing 15-20 pet photos"
  echo "  --output    Output LoRA filename (e.g., bubu-golden.safetensors)"
  echo "  --trigger   Trigger word (default: bubu_golden)"
  echo "  --steps     Training steps (default: 1500)"
  echo "  --rank      LoRA rank (default: 16)"
  exit 1
fi

echo "=== OpenPaw LoRA Training ==="
echo "Images:  $IMAGES_DIR"
echo "Output:  $OUTPUT_FILE"
echo "Trigger: $TRIGGER_WORD"
echo "Steps:   $STEPS"
echo "Rank:    $RANK"
echo ""

# Count images
IMG_COUNT=$(find "$IMAGES_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) | wc -l)
echo "Found $IMG_COUNT images"

if [ "$IMG_COUNT" -lt 10 ]; then
  echo "Warning: Recommend at least 15-20 images for good LoRA quality"
fi

# Create captions (simple auto-caption)
echo ""
echo "=== Generating captions ==="
for img in "$IMAGES_DIR"/*.{jpg,jpeg,png,webp}; do
  [ -f "$img" ] || continue
  base="${img%.*}"
  if [ ! -f "${base}.txt" ]; then
    echo "${TRIGGER_WORD}, golden retriever, photo" > "${base}.txt"
    echo "  Captioned: $(basename $img)"
  fi
done

# Training config
CONFIG_FILE=$(mktemp /tmp/lora-config-XXXX.yaml)
cat > "$CONFIG_FILE" << EOF
job: extension
config:
  name: "openpaw-${TRIGGER_WORD}"
  process:
    - type: sd_trainer
      training_folder: "${IMAGES_DIR}"
      output:
        path: "$(dirname $OUTPUT_FILE)"
        filename: "$(basename $OUTPUT_FILE .safetensors)"
      network:
        type: lora
        linear: ${RANK}
        linear_alpha: ${RANK}
      train:
        batch_size: ${BATCH_SIZE}
        steps: ${STEPS}
        lr: ${LR}
        resolution: ${RESOLUTION}
        gradient_checkpointing: true
        optimizer: adamw8bit
      model:
        name_or_path: "black-forest-labs/FLUX.1-schnell"
        is_flux: true
      trigger_word: "${TRIGGER_WORD}"
      save:
        save_every: 500
EOF

echo ""
echo "=== Config ==="
cat "$CONFIG_FILE"
echo ""

# Check if ai-toolkit is available
if command -v python3 -c "import toolkit" &> /dev/null; then
  echo "=== Starting LoRA training ==="
  python3 -m toolkit.job "$CONFIG_FILE"
  echo ""
  echo "=== Training complete ==="
  echo "LoRA saved to: $OUTPUT_FILE"
  echo ""
  echo "Copy to ComfyUI:"
  echo "  cp $OUTPUT_FILE ~/ComfyUI/models/loras/"
else
  echo "=== ai-toolkit not found ==="
  echo "Install: pip install ai-toolkit"
  echo "Or use kohya-ss/sd-scripts:"
  echo "  git clone https://github.com/kohya-ss/sd-scripts"
  echo ""
  echo "Config saved to: $CONFIG_FILE"
  echo "Adjust and run manually with your preferred trainer."
fi

# Cleanup
rm -f "$CONFIG_FILE"
