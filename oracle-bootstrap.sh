#!/usr/bin/env bash
# ============================================================
# Oracle Cloud 免费 ARM 服务器 — xray REALITY 一键部署
#
# 用法（在服务器上以 root 执行）：
#   curl -fsSL https://raw.githubusercontent.com/sy-xn/campus-tunnel/main/oracle-bootstrap.sh | sudo bash
# 或先下载再跑：
#   sudo bash oracle-bootstrap.sh
#
# 可选环境变量：
#   SNI=www.microsoft.com   伪装的目标站点（默认 www.microsoft.com）
#   PORT=443                监听端口
#
# 结束后会把客户端参数打印出来，同时存到 /root/xray-client.txt
# ============================================================

set -euo pipefail

SNI="${SNI:-www.microsoft.com}"
PORT="${PORT:-443}"

echo "=============================================="
echo " xray REALITY 部署"
echo " 伪装域名: $SNI    端口: $PORT"
echo "=============================================="

# ---------- 0. 基本检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  echo "!! 请用 root 执行（sudo bash $0）"
  exit 1
fi

ARCH=$(uname -m)
echo "[*] 架构: $ARCH （Oracle 免费实例通常是 aarch64）"

# ---------- 1. 依赖 ----------
echo "[*] 安装依赖…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq curl jq openssl ca-certificates netfilter-persistent iptables-persistent >/dev/null

# ---------- 2. 安装 xray ----------
if ! command -v xray >/dev/null 2>&1; then
  echo "[*] 安装 xray…"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
  echo "[*] xray 已存在: $(xray version | head -1)"
fi

# ---------- 3. 生成 REALITY 参数 ----------
echo "[*] 生成密钥…"
UUID=$(xray uuid)
KEYPAIR=$(xray x25519)
PRIV=$(echo "$KEYPAIR" | awk '/[Pp]rivate/{print $NF}')
PUB=$(echo "$KEYPAIR" | awk '/[Pp]ublic/{print $NF}')
SID=$(openssl rand -hex 8)

if [ -z "$PRIV" ] || [ -z "$PUB" ]; then
  echo "!! 密钥生成失败，xray x25519 输出："
  echo "$KEYPAIR"
  exit 1
fi

# ---------- 4. 写配置 ----------
echo "[*] 写入配置…"
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIV}",
          "shortIds": ["${SID}"]
        }
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

# ---------- 5. 防火墙（Oracle 有两层，这是第一层）----------
echo "[*] 配置本机防火墙…"
iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true

# Ubuntu 上的 ufw（若启用）
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
  echo "    ufw 已放行 ${PORT}/tcp"
fi

# 持久化 iptables
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save >/dev/null 2>&1 || true
  echo "    iptables 规则已持久化"
fi

# ---------- 6. 内核优化 ----------
echo "[*] 开启 BBR…"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf 2>/dev/null; then
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1 || true

# ---------- 7. 启动 ----------
echo "[*] 启动服务…"
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2

# ---------- 8. 自检 ----------
echo ""
echo "=============== 自检 ==============="
systemctl is-active xray && echo "  服务: 运行中" || echo "  服务: 未运行 !!"
if ss -ltnp 2>/dev/null | grep -q ":${PORT}"; then
  echo "  监听: ${PORT} 正常"
  ss -ltnp 2>/dev/null | grep ":${PORT}"
else
  echo "  监听: ${PORT} 失败 !!"
fi

PUBIP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || \
        curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || echo "获取失败")
echo "  公网 IP: ${PUBIP}"

# ---------- 9. 输出客户端参数 ----------
OUT=/root/xray-client.txt
cat > "$OUT" <<EOF
===== xray REALITY 客户端参数 =====
服务器地址   ${PUBIP}
端口         ${PORT}
UUID         ${UUID}
公钥(pbk)    ${PUB}
shortId      ${SID}
伪装SNI      ${SNI}
流控(flow)   xtls-rprx-vision
传输         tcp
===================================
EOF

echo ""
cat "$OUT"
echo ""
echo "参数已保存到 ${OUT}"
echo ""
echo "=============================================================="
echo " 还差一步（Oracle 第二层防火墙，必须在网页上做）："
echo ""
echo "  Oracle 控制台 → 你的实例 → 点进 VCN → Security Lists"
echo "  → 默认安全列表 → Add Ingress Rule"
echo "      Source CIDR : 0.0.0.0/0"
echo "      IP Protocol : TCP"
echo "      Destination Port Range : ${PORT}"
echo ""
echo "  不加这条，外部永远连不进来。"
echo "=============================================================="