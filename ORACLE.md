# Oracle Cloud 免费服务器部署指南

目标：拿到一台 **永久免费、24 小时在线、不休眠** 的 ARM 服务器，跑 xray REALITY，
换任何网络（校园网 / 家宽 / 手机流量）都能用。

---

## 为什么换掉 Codespaces

| | Codespaces | Oracle 免费 ARM |
|---|---|---|
| 时长 | 60 小时/月 | **无限** |
| 休眠 | 30 分钟自动停 | **不休眠** |
| 端口 | 有 Public/Private 坑 | 就是普通公网 IP |
| 协议 | 只能 WS over HTTP | **REALITY / Hysteria2 随意选** |
| 流量 | 受限 | **10 TB/月出站** |
| 稳定性 | 容器随时被回收 | 长期运行 |

---

## 一、注册

1. 打开 https://signup.oraclecloud.com
2. 国家选 **中国**（或你所在地区），邮箱用常用邮箱（QQ/Gmail 都行）
3. **需要一张信用卡**（Visa / Mastercard / 银联部分可用）做身份验证
   - 会冻结 **$1**，验证完自动退回，不会真扣款
   - 没有信用卡的话，可用家人的，或部分虚拟卡
4. 手机号验证
5. 选择 **Home Region**：优先选 **Japan East (Tokyo)** 或 **Singapore**，
   延迟低、免费 ARM 容量相对充足。**这个选择后不能改，慎重。**

> 注册后进入控制台，左上角可以切换语言为中文。

---

## 二、创建实例

控制台 → 左上角菜单 → **计算 → 实例** → **创建实例**

| 字段 | 填什么 |
|---|---|
| 名称 | `xray`（随意） |
| 区间 | 保持默认（root） |
| **映像** | **Canonical Ubuntu** → **24.04**（**必须选 aarch64/ARM 版**） |
| **形状** | 选 **Ampere** → `VM.Standard.A1.Flex` |
| OCPU / 内存 | **4 OCPU / 24 GB**（这是免费额度上限，可先用 2/12 更容易开出来） |
| 主网络 | 默认 VCN（会自动创建） |
| 分配公共 IPv4 | **勾选** |
| SSH 密钥 | 选 **生成密钥对** → **下载私钥**（务必保存好） |

点 **创建**。

> **如果提示 "Out of capacity"**：ARM 免费实例经常缺货。
> 换一个可用性域（Availability Domain 1/2/3）重试；
> 或把 OCPU 降到 2、内存降到 12；
> 或过几小时再试。这是 Oracle 的老毛病，不是你的问题。

---

## 三、开放 443 端口（最关键的一步）

Oracle 有**两层防火墙**，脚本只能改第二层，第一层必须在这里手动加。

### 3.1 云平台安全列表

控制台 → **网络 → 虚拟云网络** → 点你的 VCN → 左侧 **安全列表** → 点 **Default Security List**

**添加入站规则**：

| 字段 | 值 |
|---|---|
| 源类型 | CIDR |
| 源 CIDR | `0.0.0.0/0` |
| IP 协议 | TCP |
| 目标端口范围 | `443` |

**再按同样方式加一条 UDP 443**（如果以后想用 Hysteria2）。

> 不加这条，不管服务器上怎么配，外面永远连不进来。这是 90% 新手卡住的地方。

### 3.2 本机 iptables

脚本会自动处理，不用你管。

---

## 四、SSH 登录

在实例详情页复制 **公共 IP**（形如 `140.238.x.x`）。

Windows PowerShell 里：

```powershell
# 把私钥路径换成你下载的那个
ssh -i "C:\Users\ASUS\Downloads\ssh-key-2026-11-10.key" ubuntu@140.238.x.x
```

> 私钥文件权限太宽会被拒。如果报 `bad permissions`：
> ```powershell
> icacls "C:\Users\ASUS\Downloads\ssh-key-2026-11-10.key" /inheritance:r /grant:r "$($env:USERNAME):(R)"
> ```

登录后提示符会变成 `ubuntu@xray:~$`。

---

## 五、一键部署

在服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/sy-xn/campus-tunnel/main/oracle-bootstrap.sh | sudo bash
```

脚本会自动完成：

1. 装依赖
2. 装 xray
3. 生成 UUID、REALITY 密钥对、shortId
4. 写配置（VLESS + REALITY，伪装 `www.microsoft.com`）
5. 开本机防火墙 443
6. 开 BBR 加速
7. 启动服务 + 自检
8. **打印客户端参数**，同时存到 `/root/xray-client.txt`

### 期望输出

```
=============== 自检 ===============
  服务: 运行中
  监听: 443 正常
LISTEN 0 4096 *:443 *:* users:(("xray",pid=1234,fd=6))
  公网 IP: 140.238.x.x

===== xray REALITY 客户端参数 =====
服务器地址   140.238.x.x
端口         443
UUID         xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
公钥(pbk)    xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
shortId      xxxxxxxxxxxxxxxx
伪装SNI      www.microsoft.com
流控(flow)   xtls-rprx-vision
传输         tcp
===================================
```

**把这 4 个参数发我**：服务器地址、UUID、公钥、shortId。

---

## 六、生成客户端配置

拿到参数后，我在本地执行：

```powershell
cd D:\dsh工作区\日常对话\campus-net\breakout
python setup_clash.py `
  --uuid <UUID> `
  --pbk <公钥> `
  --sid <shortId> `
  --reality-host <服务器IP> `
  --reality-name "Oracle-REALITY" `
  --preset carrier
```

会自动写入 Clash Verge、设为当前配置、重启生效。

---

## 七、验证

```powershell
python D:\dsh工作区\日常对话\campus-net\test_proxy.py
```

期望 `成功 7/7`。

---

## 常见问题

**Q: SSH 连不上 / 超时**
- 确认实例状态是「运行中」
- 确认用的是 `ubuntu` 用户（不是 root）
- 确认安全列表里 SSH（22）规则没被删（Oracle 默认有）

**Q: 脚本跑完，但 Clash 连不上**
按这个顺序查：
```bash
# 服务器上
sudo systemctl status xray          # 是否运行
sudo ss -ltnp | grep 443            # 是否监听
sudo tail -30 /var/log/xray/error.log   # 有无报错
```
然后确认云平台安全列表加了 443（第三节）。

**Q: 连上了但很慢**
- 检查 Home Region 是不是选太远（选东京/新加坡最好）
- 确认开了 BBR：`sysctl net.ipv4.tcp_congestion_control` 应输出 `bbr`
- ARM 实例性能有限，跑满带宽没问题，但别指望超大并发

**Q: 想换伪装域名**
服务器上编辑 `/usr/local/etc/xray/config.json`，把两处 `www.microsoft.com` 改掉，
然后 `sudo systemctl restart xray`。客户端也要对应改 `--sni`。

**推荐伪装域名**（都支持 TLS1.3 + HTTP/2，且国内访问快）：
```
www.microsoft.com
www.apple.com
dl.google.com
www.cloudflare.com
```

**Q: 会不会被 Oracle 封号**
免费额度内正常使用一般没问题。注意：
- 不要跑挖矿、不发垃圾邮件
- 不要开一堆小号
- 出站流量控制在 10TB/月内

---

## 附：REALITY 为什么比 WS 好

| | WS + TLS（Codespaces） | REALITY（Oracle） |
|---|---|---|
| 需要域名 | 是 | **否** |
| 需要证书 | 是 | **否** |
| 抗 SNI 封锁 | 依赖域名在白名单 | **伪装成真实站点，无法区分** |
| 抗主动探测 | 弱 | **强（探测者会被转发到真站点）** |
| 性能 | 多一层 WS 封装 | **原生 TCP + XTLS Vision，更快** |

REALITY 的原理：服务器不持有自己的证书，而是**借用** `www.microsoft.com` 的证书响应。
客户端用预共享公钥验证，验证不通过的人会被当作普通访客，直接被转发去微软官网 ——
所以中间设备看到的、探测到的，都是一个正常的 HTTPS 连接。