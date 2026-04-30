# OpenPaw 啟動 SOP

**目標**: 讓金金在 LINE + Discord 上線，包含 cronjob 每日推播 + 產圖

---

## 前置條件

```
✅ 已完成：
├── ComfyUI 安裝 (/home/bklinu/ComfyUI)
├── Flux.1-schnell FP8 模型下載
├── GPU 分工驗證（GPU0=Ollama, GPU1=ComfyUI）
├── openpaw repo (github.com/BlakeHung/openpaw)
└── 金金 persona + config + cronjob 設定

需要你提供：
├── Discord Bot Token
├── Discord 頻道 ID
├── LINE Channel Secret
├── LINE Channel Access Token
├── 咘咘照片 15-20 張（LoRA 訓練用）
└── Public HTTPS domain（LINE webhook 用）
```

---

## Step 1: Discord Bot 設定

### 1.1 建立 Discord Bot（如果還沒有）

1. 到 https://discord.com/developers/applications
2. New Application → 名稱：`金金`
3. Bot 頁面 → Reset Token → 複製 **Bot Token**
4. 開啟 Privileged Gateway Intents：
   - ✅ Message Content Intent
   - ✅ Server Members Intent
5. OAuth2 → URL Generator：
   - Scopes: `bot`
   - Permissions: `Send Messages`, `Read Message History`, `Attach Files`, `Add Reactions`
6. 用產生的 URL 邀請 bot 到你的 server

### 1.2 取得頻道 ID

1. Discord 設定 → 進階 → 開啟「開發者模式」
2. 右鍵目標頻道 → 複製頻道 ID

```bash
# 記下來
export DISCORD_BOT_TOKEN="你的token"
export DISCORD_CHANNEL_ID="你的頻道ID"
```

---

## Step 2: LINE 設定

### 2.1 建立 LINE Official Account

1. 到 https://manager.line.biz
2. 建立新帳號
   - 名稱：`金金 - 寵物照護 AI`
   - 類別：寵物

### 2.2 開啟 Messaging API

1. Settings → Messaging API → Enable Messaging API
2. 選擇或建立 Provider（例：`OpenPaw`）
3. 確認

### 2.3 取得 Credentials

到 https://developers.line.biz → 開啟你的 channel：

1. **Basic settings** → Channel secret → 複製
2. **Messaging API** → 最底部 → Channel access token → Issue → 複製

```bash
export LINE_CHANNEL_SECRET="你的secret"
export LINE_CHANNEL_ACCESS_TOKEN="你的token"
```

### 2.4 設定 Webhook

LINE Developers Console → Messaging API：

1. Webhook URL → `https://你的domain/webhook/line`
2. Use webhook → **ON**
3. Auto-reply messages → **OFF**
4. 點 Verify 測試

### 2.5 Public HTTPS（LINE webhook 需要）

方案 A — Cloudflare Tunnel（推薦）：
```bash
# 安裝
brew install cloudflared  # 或 apt install cloudflared

# 建立 tunnel 指向 gateway port 8080
cloudflared tunnel --url http://localhost:8080
# → 會給你一個 https://xxx.trycloudflare.com
# → 把這個填到 LINE webhook URL
```

方案 B — ngrok：
```bash
ngrok http 8080
# → https://xxx.ngrok-free.app
```

---

## Step 3: OpenAB + Gateway 啟動

### 3.1 啟動 Gateway（LINE 用）

```bash
docker run -d --name openab-gateway \
  -e LINE_CHANNEL_SECRET="${LINE_CHANNEL_SECRET}" \
  -e LINE_CHANNEL_ACCESS_TOKEN="${LINE_CHANNEL_ACCESS_TOKEN}" \
  -p 8080:8080 \
  ghcr.io/openabdev/openab-gateway:0.3.0
```

驗證：
```bash
curl http://localhost:8080/health
# → ok
```

### 3.2 設定 config.toml

```bash
cd /home/bklinu/devProject/openab
cp /home/bklinu/devProject/openpaw/configs/jin-jin.toml config.toml
```

編輯 `config.toml`，填入實際值：

```toml
[discord]
bot_token = "${DISCORD_BOT_TOKEN}"
allowed_channels = ["你的頻道ID"]

[gateway]
url = "ws://localhost:8080/ws"
platform = "line"

[agent]
command = "claude"
args = ["code", "--trust-all-tools"]
working_dir = "/home/bklinu/devProject/openpaw/agents/jin-jin"
env = { ANTHROPIC_API_KEY = "${ANTHROPIC_API_KEY}" }

[pool]
max_sessions = 5
session_ttl_hours = 24

[reactions]
enabled = true

[markdown]
format = "bullets"

[cron]
usercron_enabled = true
usercron_path = "cronjob.toml"
```

### 3.3 設定 cronjob.toml

```bash
cp /home/bklinu/devProject/openpaw/configs/cronjob.toml cronjob.toml
```

編輯 `cronjob.toml`，填入頻道 ID：

```toml
# 每個 [[jobs]] 的 channel 欄位填入：
# Discord: 頻道 ID
# LINE: user ID 或 group ID

[[jobs]]
schedule = "0 8 * * *"
channel = "你的頻道ID"        # ← 改這裡
platform = "discord"          # 或 "line"（透過 gateway）
sender_name = "金金"
timezone = "Asia/Taipei"
message = """..."""
```

### 3.4 啟動 OpenAB

```bash
cd /home/bklinu/devProject/openab
cargo run -- --config config.toml
```

---

## Step 4: ComfyUI 產圖服務

### 4.1 啟動 ComfyUI（GPU 1）

```bash
cd /home/bklinu/ComfyUI
CUDA_VISIBLE_DEVICES=1 nohup python3 main.py \
  --listen 0.0.0.0 --port 8188 > /tmp/comfyui.log 2>&1 &
```

驗證：
```bash
curl -s http://localhost:8188/system_stats | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['devices'][0]['name'])"
# → cuda:0 NVIDIA GeForce RTX 3090
```

### 4.2 測試產圖

```bash
cd /home/bklinu/devProject/openpaw
./comfyui/generate-and-send.sh \
  --prompt "a happy golden retriever, sunny day, cute" \
  --platform discord \
  --channel "${DISCORD_CHANNEL_ID}" \
  --caption "金金測試圖！汪！"
```

---

## Step 5: LoRA 訓練（咘咘風格）

### 5.1 準備照片

```bash
mkdir -p /home/bklinu/devProject/openpaw/lora/training/images

# 把咘咘的照片放進去（15-20 張）
# 不同角度、表情、場景
# 支援 jpg/jpeg/png/webp
```

### 5.2 安裝訓練工具

```bash
pip install ai-toolkit
# 或
git clone https://github.com/kohya-ss/sd-scripts
```

### 5.3 訓練

```bash
cd /home/bklinu/devProject/openpaw/lora/training
./train-lora.sh \
  --images ./images \
  --output /home/bklinu/ComfyUI/models/loras/bubu-golden.safetensors \
  --trigger bubu_golden \
  --steps 1500
```

### 5.4 驗證 LoRA

```bash
cd /home/bklinu/devProject/openpaw
./comfyui/generate-and-send.sh \
  --prompt "bubu_golden, golden retriever saying good morning, cute" \
  --lora "bubu-golden.safetensors" \
  --platform discord \
  --channel "${DISCORD_CHANNEL_ID}" \
  --caption "咘咘風格測試！"
```

---

## Step 6: 驗證清單

### Discord

```
□ Bot 在 server 中
□ @金金 打招呼 → 收到回覆
□ 問寵物問題 → AI 搜尋資料回答
□ Cronjob 早安 → 08:00 自動推送
□ 產圖指令 → 圖片傳回 thread
```

### LINE

```
□ 加金金好友（掃 QR code）
□ 傳訊息 → 收到回覆
□ 問「狗可以吃葡萄嗎」→ 搜尋回答
□ Cronjob → 每日推送
```

### 產圖

```
□ ComfyUI 在 GPU 1 運行中
□ API 產圖成功
□ LoRA 訓練完成（有咘咘照片後）
□ LoRA 產圖 = 咘咘風格
```

---

## 服務管理

### 啟動所有服務

```bash
# 1. ComfyUI (GPU 1)
cd /home/bklinu/ComfyUI
CUDA_VISIBLE_DEVICES=1 nohup python3 main.py \
  --listen 0.0.0.0 --port 8188 > /tmp/comfyui.log 2>&1 &

# 2. Gateway (LINE)
docker start openab-gateway

# 3. OpenAB
cd /home/bklinu/devProject/openab
cargo run -- --config config.toml
```

### 停止所有服務

```bash
# ComfyUI
pkill -f "ComfyUI/main.py"

# Gateway
docker stop openab-gateway

# OpenAB
Ctrl+C（或 kill PID）
```

### 查看狀態

```bash
# GPU 使用
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv,noheader

# ComfyUI
curl -s http://localhost:8188/system_stats | python3 -c \
  "import sys,json; print('ComfyUI OK')" 2>/dev/null || echo "ComfyUI down"

# Gateway
curl http://localhost:8080/health

# Ollama
ollama list
```

### 更新 Cronjob（不需重啟）

```bash
# 直接編輯 cronjob.toml，1 分鐘內自動生效
vim /home/bklinu/devProject/openab/cronjob.toml
```

---

## 環境變數總覽

```bash
# Discord
DISCORD_BOT_TOKEN=
DISCORD_CHANNEL_ID=

# LINE
LINE_CHANNEL_SECRET=
LINE_CHANNEL_ACCESS_TOKEN=

# AI
ANTHROPIC_API_KEY=

# ComfyUI
COMFYUI_API_URL=http://localhost:8188

# Imgur（LINE 產圖上傳用，optional）
IMGUR_CLIENT_ID=
```

---

## 故障排除

| 問題 | 原因 | 解法 |
|------|------|------|
| Discord bot 沒回應 | Bot token 錯 or 沒加頻道 | 檢查 allowed_channels |
| LINE 沒回應 | Webhook URL 錯 or Auto-reply ON | LINE Console 檢查 |
| Cronjob 沒觸發 | 頻道 ID 沒填 or 時區錯 | 檢查 cronjob.toml |
| 產圖 OOM | 用了全精度模型 | 改用 FP8: `flux1-schnell-fp8-e4m3fn.safetensors` |
| ComfyUI 連不上 | 沒啟動 or port 錯 | `curl localhost:8188/system_stats` |
| Gateway health fail | Docker 沒跑 | `docker start openab-gateway` |
