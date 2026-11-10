#!/usr/bin/env bash
# 在 GitHub Codespaces 里一键装好 xray 隧道并启动
#
# 用法（在 Codespace 终端里）：
#   chmod +x codespace-setup.sh
#   ./codespace-setup.sh <你的UUID>
#
# 之后：Ports 面板 → 8080 → 右键 → Port Visibility → Public
#      拿到的 https://<codespace名>-8080.app.github.dev 就是你的入口

set -euo pipefail

UUID="${1:-}"
if [ -z "$UUID" ]; then
  echo "用法: $0 <UUID>"
  echo "生成 UUID: python3 -c 'import uuid;print(uuid.uuid4())'"
  exit 1
fi

echo "==> UUID: $UUID"
echo "==> 安装 xray"

# Codespaces 内部有完整互联网，不受校园网限制，可直接装
if ! command -v xray >/dev/null 2>&1; then
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
  echo "    xray 已存在: $(xray version | head -1)"
fi

echo "==> 写配置"
CFG="$HOME/xray-config.json"
cat > "$CFG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "flow": "" }],
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
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
    ]
  }
}
EOF

echo "==> 启动"
pkill -f "xray run" 2>/dev/null || true
sleep 1
nohup xray run -c "$CFG" > "$HOME/xray.log" 2>&1 &
sleep 2

if pgrep -f "xray run" >/dev/null; then
  echo "==> xray 已启动 (pid $(pgrep -f 'xray run' | head -1))"
else
  echo "!! 启动失败，日志："
  tail -30 "$HOME/xray.log"
  exit 1
fi

echo ""
echo "================================================================"
echo " 下一步（必做）："
echo "  1. 打开下方 Ports 面板（或 VSCode 的 PORTS 标签）"
echo "  2. 找到 8080 端口 → 右键 → Port Visibility → Public"
echo "  3. 复制形如 https://xxxxx-8080.app.github.dev 的地址"
echo "  4. 本地运行："
echo "       python make_config.py --service xxxxx-8080.app.github.dev --uuid $UUID"
echo "================================================================"
echo ""
echo "自检：浏览器打开 https://<转发域名>/ws"
echo "      看到 400 / 426 就说明 xray 活着"
