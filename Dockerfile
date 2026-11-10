FROM ghcr.io/xtls/xray-core:latest

# 服务端配置：VLESS + WebSocket，明文监听 8080
# TLS 由 PaaS 平台在边缘终止（https://<name>.koyeb.app），容器内无需证书
COPY config.json /etc/xray/config.json

EXPOSE 8080

# -format json 让日志可读；容器被平台探活请求驱动
CMD ["xray", "run", "-c", "/etc/xray/config.json"]