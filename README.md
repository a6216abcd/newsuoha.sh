# New-Suoha: 全协议一键梭哈部署脚本 (Sing-box 主力 + 单 Argo 双路径 + Snell + SS-IPv6)

轻量、极速、零交互、开箱即用的全协议代理一键部署脚本。基于 **官方原版 Sing-box 核心** 与 **Cloudflare Argo 临时隧道**，结合轻量级异步路由分发器与 **Snell v4** 官方服务端，一条命令即可在主流 Linux VPS 上全自动部署 **9 种主流直连与 CDN 隧道协议**。内置**永久固定订阅端口**托管服务，支持订阅无缝刷新及主流客户端一键导入。

---

## 致谢与致敬 (Acknowledgments)

本项目基于开源社区优秀成果深度重构与升级，在此特别鸣谢：

- **原版梭哈脚本**：感谢 [jwfst5088/suoha.sh](https://github.com/jwfst5088/suoha.sh) 开拓性的灵感启发与基础实现，经典梭哈模式为轻量化 Argo 部署奠定了极简实用的体验基础。

- **Cloudflare 优选节点提供方**：感谢社区与站长们无私维护并分享的高质量 Cloudflare 优选 CDN 域名（如 `cf.090227.xyz`、`cloudflare.182682.xyz` 等），极大改善了国内到 Cloudflare 边缘网络的延迟与连接质量。

- **SagerNet、Cloudflare 与 Surge**：感谢 [SagerNet/sing-box](https://github.com/SagerNet/sing-box)、[cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) 与 [Surge Snell](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) 提供的底层核心技术支持。

---

## 核心特性

- **多架构与多系统适配**：原生支持 `x86_64`、`arm64`、`armv7l`、`i386` 架构；全面适配 Debian、Ubuntu、CentOS、Fedora 及 Alpine Linux。

- **全自动零交互部署**：无需手动输入参数或准备自有域名，脚本自动探测公网 IPv4 / IPv6 双栈环境、自动签发 `www.bing.com` 自签名 TLS 证书与 Reality X25519 密钥对，并自动放行系统防火墙 (`ufw` / `firewalld` / `iptables` / `ip6tables`)。

- **单 Argo 隧道双路径复用**：通过内置的轻量级 Python `asyncio` 本地分流守护进程，仅申请一条 `*.trycloudflare.com` 临时隧道即可按路径同时分发 **VLESS-WS** (`/vl-xxx`) 与 **Trojan-WS** (`/tr-xxx`) 双协议；内置 HTTP/2 与 QUIC 超时自动切换重连机制，并矩阵式生成 **3 组优选域名**（`默认 Argo 域名`、`cf.090227.xyz`、`cloudflare.182682.xyz`）的 443 TLS 节点。

- **全主流直连协议矩阵并发**：在单一官方 Sing-box 进程内原生并发监听以下直连抗封锁与高速协议，同时拉起原生 Snell v4 双栈守护进程：
  - **VLESS-Reality-Vision** (`xtls-rprx-vision` + `www.bing.com` 伪装，主力首选)
  - **VLESS-Reality-gRPC** (`gun` 多路复用 + `www.bing.com` 伪装)
  - **AnyTLS** (动态 Padding 策略 + 自签 `www.bing.com`)
  - **Hysteria2** (QUIC + `h3` ALPN + 自签 `www.bing.com`)
  - **TUIC v5** (QUIC + BBR + Native UDP Relay)
  - **Snell v4 双栈** (原生 `::0` 双栈监听，独立输出 IPv4 与 IPv6 节点配置)
  - **Shadowsocks IPv6** (`aes-128-gcm`，自动探测 IPv6 输出原生直连节点)
  - *(注：XHTTP 入站节点已暂时屏蔽，待官方 Sing-box 稳定版原生完善后同步开放)*

- **永久固定订阅端口（免重复导入）**：
  - 首次运行自动分配并持久化记录订阅端口（存储于 `/etc/suoha_sub_port`）；
  - 静态订阅文件集中托管于 `/var/www/suoha_sub/`，重新执行脚本刷新节点或重启重新梭哈后，**客户端无需重新导入链接，直接点击“更新订阅”即可自动刷新最新节点**。

---

## 一键运行命令

登录 VPS 终端（支持 root 用户），执行以下命令即可全自动完成部署：

```bash
bash -c "$(curl -fsSL [https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh](https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh))"
