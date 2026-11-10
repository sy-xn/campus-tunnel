#!/usr/bin/env bash
# 由 .devcontainer/devcontainer.json 的 postStartCommand 自动调用
# 作用：Codespace 每次启动时自动把 xray 拉起来（幂等，已在跑就跳过）

set -uo pipefail

UUID="${UUID:-35916eea-5346-4623-8f90-df0a8bf92f5a}"
PORT="${PORT:-8080}"
DIR="$HOME/xray"
LOG="$DIR/xray.log"

echo "[tunnel] ---- $(date '+%F %T') ----"
mkdir -p "$DIR" && cd "$DIR" || { echo "[tunnel] 无法进入 $DIR"; exit 0; }

# 已在运行则跳过
if pgrep -f "xray run -c" >/dev/null 2>&1; then
  echo "[tunnel] 已在运行 pid=$(pgrep -f 'xray run -c' | head -1)，跳过"
  exit 0
fi

# 依赖
missing=""
for c in curl python3; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
if [ -n "$missing" ]; then
  echo "[tunnel] 补装依赖:$missing"
  sudo apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq curl python3 unzip >/dev/null 2>&1
fi

# 二进制
if [ ! -x ./xray ]; then
  arch=$(uname -m)
  case "$arch" in
    aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
    *)             asset="Xray-linux-64.zip" ;;
  esac
  echo "[tunnel] 下载 xray ($arch -> $asset)…"
  if ! curl -fsSL -o x.zip "https://github.com/XTLS/Xray-core/releases/latest/download/$asset"; then
    echo "[tunnel] !! 下载失败"
    exit 0
  fi
  python3 -c "import zipfile;zipfile.ZipFile('x.zip').extractall('.')" || {
    echo "[tunnel] !! 解压失败"; exit 0; }
  chmod +x xray
fi

# 配置
cat > config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/ws" }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF

# 启动
nohup ./xray run -c config.json > "$LOG" 2>&1 &
sleep 3

if pgrep -f "xray run -c" >/dev/null 2>&1; then
  echo "[tunnel] ✓ 已启动 pid=$(pgrep -f 'xray run -c' | head -1)"
  curl -s -o /dev/null -w "[tunnel] 本地自检 code=%{http_code}（400 为正常）\n" \
    "http://127.0.0.1:${PORT}/ws" || true
else
  echo "[tunnel] !! 启动失败，日志："
  tail -20 "$LOG" 2>/dev/null || echo "(无日志)"
fi