# OpenPaw — My Pet Anywhere

Pet AI assistant built on [OpenAB](https://github.com/openabdev/openab). Train your pet's face with LoRA, deploy on LINE — your pet greets your family every morning.

**Fork → Config → Deploy**

![BuBu](https://wchung.tw/recon/images/20260505-openpaw-bubu-cover-4_4bd4ff44-0.png)

---

## What it does

- **LoRA-trained image generation** — AI generates images that look like your actual pet
- **Daily push** — weather + pet care tips + AI-generated greeting image via cronjob
- **Multi-platform** — LINE / Discord / Slack / Telegram / Feishu / Google Chat
- **Emotion-aware** — detects owner's mood, adjusts response
- **Text overlay** — Chinese text on images (Pillow + Noto Sans CJK)
- **Brand persona** — change `CLAUDE.md` to switch voice and personality

## Architecture

```
LINE / Discord
    → Cloudflare Tunnel
    → Gateway (Rust, axum, HMAC signature verification)
    → OpenAB Core (Session Pool + Cronjob + Keyword Gating)
    → Claude Code Agent (pet persona via CLAUDE.md)
    → ComfyUI + Flux.1 + LoRA (image generation, ~10s)
    → Pillow (text overlay)
    → LINE Push API / Discord API
```

## BuBu — Reference Implementation

BuBu (咘咘) is a golden retriever, the first OpenPaw pet AI. Running in a real family LINE group:

- Checks local weather every morning
- Generates a greeting image with her face
- Reminds family to take her for a walk
- Responds when you call her name
- Auto-introduces herself when joining a new group

## Quick Start

```bash
# 1. Clone
git clone https://github.com/BlakeHung/openpaw.git

# 2. Set up OpenAB
git clone https://github.com/openabdev/openab.git
cd openab
cp ../openpaw/configs/jin-jin-line.toml config.toml
cp ../openpaw/configs/cronjob.toml cronjob.toml

# 3. Configure
# Edit config.toml — add LINE token, channel secret
# Edit CLAUDE.md — define your pet's personality
# Edit cronjob.toml — set schedule and channel IDs

# 4. Run
cargo run -- -c config.toml
```

## Image Generation

```bash
# Train LoRA (collect 20+ photos of your pet)
cd lora/training
./train-lora.sh --images /path/to/pet-photos --output your-pet.safetensors

# Generate + send
./comfyui/generate-and-send.sh \
  --prompt "your_pet_trigger, golden retriever in sunny morning" \
  --platform line \
  --channel "your-channel-id" \
  --caption "Good morning!"
```

## Why OpenAB, not OpenClaw

OpenClaw (60K stars) has had multiple CVEs in 2026 — RCE, privilege escalation, 40K+ exposed instances, 335 malicious Skills.

OpenAB is different by design:
- Agent has stdio only (ACP protocol), no OS access
- No marketplace = no supply chain risk
- Rust = memory safe
- Config-driven = auditable

## Directory Structure

```
openpaw/
├── agents/jin-jin/CLAUDE.md    # Pet persona
├── configs/
│   ├── jin-jin-line.toml       # LINE config
│   └── cronjob.toml            # Schedule
├── comfyui/
│   ├── generate-and-send.sh    # Image pipeline
│   ├── overlay-text.py         # Chinese text overlay
│   └── workflows/              # ComfyUI workflow
├── lora/training/              # LoRA training
└── docs/
    ├── reboot-guide.md         # Server restart guide
    └── sendimages.md           # Image delivery protocol
```

## Cost

~$115/month (Claude Max $100 + GPU electricity ~$15)

## Links

- **Blog**: [wchung.tw/blog/openpaw-ai-pet-on-line](https://wchung.tw/blog/openpaw-ai-pet-on-line/)
- **Landing**: [wchung.tw/OpenPaw](https://wchung.tw/OpenPaw/)
- **OpenAB**: [github.com/openabdev/openab](https://github.com/openabdev/openab)
- **OpenAB Discord**: [discord.gg/DmbhfDZjQS](https://discord.gg/DmbhfDZjQS)
- **Author**: Blake Hung — blake@wchung.tw

## Credits

BuBu (咘咘) — [@goldenbubuisme](https://www.instagram.com/goldenbubuisme) · [@goldenbubu0504](https://www.threads.com/@goldenbubu0504)
