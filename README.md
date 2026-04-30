# 🐾 OpenPaw — My Pet Anywhere

Pet AI assistant architecture built on [OpenAB](https://github.com/openabdev/openab).

**Fork → Config → Deploy** — let your pet brand have its own AI assistant.

---

## What is OpenPaw

OpenPaw is a vertical application framework on top of OpenAB, designed for the pet industry. It provides:

- **Pet care AI Q&A** — pet owners ask via LINE/Discord, AI searches veterinary resources to answer
- **Daily push notifications** — weather reminders + pet care tips via cronjob
- **Multi-platform** — LINE (consumers) + Discord (community) with a single config
- **Brand persona** — change `CLAUDE.md` to switch voice and personality
- **Brand-specific image generation** — train LoRA on your pet/mascot photos, AI generates on-brand images

## Architecture

```
  Layer 4: Client Layer (per client)
  ├── LoRA weights (brand-specific image style)
  ├── CLAUDE.md (persona)
  ├── config.toml (platform + AI backend)
  ├── cronjob.toml (scheduled push)
  └── Knowledge base / FAQ

  Layer 3: Image Engine
  ├── ComfyUI + Flux.1-schnell
  ├── Dynamic LoRA loading (per client)
  └── sendimages protocol (Discord/LINE/Telegram)

  Layer 2: AI Agent Layer
  ├── Claude Code / Kiro / OpenCode
  ├── WebSearch + WebFetch
  └── Session management

  Layer 1: Platform Layer (OpenAB)
  ├── LINE / Discord / Telegram / Slack
  ├── CronScheduler (hot-reload)
  └── K8s / Helm / Docker
```

## Jin-Jin — Reference Implementation

Jin-Jin (金金) is a golden retriever AI assistant, the first OpenPaw pet AI:

- Pet health Q&A (diet safety, behavior, daily care)
- Find nearby vets, pet events
- Daily greeting (weather + pet care tips)
- Weekend pet activity recommendations
- Brand images generated from LoRA trained on real golden retriever photos

## Directory Structure

```
openpaw/
├── README.md
├── agents/
│   └── jin-jin/
│       └── CLAUDE.md           # Jin-Jin persona
├── configs/
│   ├── jin-jin.toml            # Agent config
│   └── cronjob.toml            # Scheduled tasks
├── comfyui/
│   └── workflows/
│       └── flux-lora-generate.json  # Image generation workflow
├── lora/
│   └── training/
│       └── train-lora.sh       # LoRA training script
└── docs/
    └── sendimages.md           # Image delivery best practices
```

## Quick Start

### Prerequisites

- [OpenAB](https://github.com/openabdev/openab) cloned and built
- Claude Code (or other ACP-compatible CLI)
- GPU with 12GB+ VRAM (for image generation)
- ComfyUI (for Flux.1 + LoRA)

### 1. Clone

```bash
git clone https://github.com/BlakeHung/openpaw.git
```

### 2. Set up OpenAB

```bash
git clone https://github.com/openabdev/openab.git
cd openab
# Copy OpenPaw configs
cp ../openpaw/configs/jin-jin.toml config.toml
cp ../openpaw/configs/cronjob.toml cronjob.toml
# Set up agent working directory
ln -s ../openpaw/agents/jin-jin agents/jin-jin
```

### 3. Configure

Edit `config.toml`:
```toml
[discord]
bot_token = "${DISCORD_BOT_TOKEN}"
allowed_channels = ["your-channel-id"]

[agent]
working_dir = "/path/to/openpaw/agents/jin-jin"
```

Edit `cronjob.toml` — fill in channel IDs.

### 4. Run

```bash
cargo run -- --config config.toml
```

## Image Generation

OpenPaw uses **LoRA-trained Flux.1** to generate brand-specific pet images.

### Train LoRA

```bash
# Collect 15-20 photos of your pet/mascot
# Run training script
cd lora/training
./train-lora.sh --images /path/to/pet-photos --output bubu-golden.safetensors
```

### Generate Images

Images are generated via ComfyUI API and delivered using the [sendimages](docs/sendimages.md) protocol — no OpenAB core modification needed.

## Customize for Your Brand

1. Copy `agents/jin-jin/` → `agents/your-pet/`
2. Edit `CLAUDE.md` — change brand name, voice, expertise
3. Copy `configs/jin-jin.toml` → `configs/your-pet.toml`
4. Train LoRA with your brand's pet/mascot photos
5. Done — each new client takes 1-2 days to deploy

## Links

- **Landing page**: [wchung.tw/OpenPaw](https://wchung.tw/OpenPaw/)
- **OpenAB**: [github.com/openabdev/openab](https://github.com/openabdev/openab)
- **Author**: Blake Hung — blake@wchung.tw

## Credits

Photo reference: 小金毛 咘咘BuBu [@goldenbubu0504](https://www.threads.com/@goldenbubu0504) (authorized)
