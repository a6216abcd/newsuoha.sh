

# New-Suoha: 全协议一键梭哈部署脚本 (4K内核调优 + Sing-box主力 + 单Argo双路径 + Snell + SS-IPv6)

轻量、极速、零交互、开箱即用的全协议代理一键部署脚本。在部署代理节点前自动应用 **1080P / 4K 高码率视频流媒体 TCP & UDP 内核级网络调优**，并基于 **官方原版 Sing-box 核心** 与 **Cloudflare Argo 临时隧道**，结合轻量级异步路由分发器与 **Snell v4** 官方服务端，一条命令即可在主流 Linux VPS 上全自动部署 **9 种主流直连与 CDN 隧道协议**。内置**永久固定订阅端口**托管服务，支持订阅无缝刷新及主流客户端一键导入。

---

## 致谢与致敬 (Acknowledgments)

本项目基于开源社区优秀成果深度重构与升级，在此特别鸣谢：

- **原版梭哈脚本**：感谢 [jwfst5088/suoha.sh](https://github.com/jwfst5088/suoha.sh) 开拓性的灵感启发与基础实现，经典梭哈模式为轻量化 Argo 部署奠定了极简实用的体验基础。

- **Cloudflare 优选节点提供方**：感谢社区与站长们无私维护并分享的高质量 Cloudflare 优选 CDN 域名（如 `cf.090227.xyz`、`cloudflare.182682.xyz` 等），极大改善了国内到 Cloudflare 边缘网络的延迟与连接质量。

- **SagerNet、Cloudflare 与 Surge**：感谢 [SagerNet/sing-box](https://github.com/SagerNet/sing-box)、[cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) 与 [Surge Snell](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) 提供的底层核心技术支持。

---

## 核心特性

- **前置 1080P / 4K 视频流媒体 TCP & UDP 内核级调优**：
  - 部署前自动写入 `/etc/sysctl.d/99-suoha-4k.conf` 并即时生效（卸载时自动清理）；
  - 强制开启 **BBR 拥塞控制 + FQ 公平队列调度**，显著提升跨洋高延迟链路的大码率吞吐与抗丢包能力；
  - **内存自适应读写缓冲窗口**：自动识别 VPS 物理内存（小于 `512MB` 机型启用 `8MB` 安全缓冲防 OOM，大于等于 `512MB` 机型启用 `32MB` 大窗口缓冲），充分喂饱 4K 60fps 视频流的高 BDP 窗口；
  - 针对 **UDP / QUIC**（Hysteria2 / TUIC v5）增大收发队列与 `netdev_max_backlog` 防止突发丢包，关闭 `tcp_slow_start_after_idle` 避免视频暂停恢复播放时降速，开启 `tcp_mtu_probing` 自动规避路由黑洞分片。

- **多架构与多系统适配**：原生支持 `x86_64`、`arm64`、`armv7l`、`i386` 架构；全面适配 Debian、Ubuntu、CentOS、Fedora 及 Alpine Linux。

- **全自动零交互部署**：无需手动输入参数或准备自有域名，脚本自动探测公网 IPv4 / IPv6 双栈环境、自动签发 `www.bing.com` 自签名 TLS 证书与 Reality X25519 密钥对，并自动放行系统防火墙 (`ufw` / `firewalld` / `iptables` / `ip6tables`)。

- **单 Argo 隧道双路径复用**：通过内置的轻量级 Python `asyncio` 本地分流守护进程（`64KB` 高速转发缓冲），仅申请一条 `*.trycloudflare.com` 临时隧道即可按路径同时分发 **VLESS-WS** (`/vl-xxx`) 与 **Trojan-WS** (`/tr-xxx`) 双协议；内置 HTTP/2 与 QUIC 超时自动切换重连机制，并矩阵式生成 **3 组优选域名**（`默认 Argo 域名`、`cf.090227.xyz`、`cloudflare.182682.xyz`）的 443 TLS 节点。

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

登录 VPS 终端（支持 root 用户），执行以下命令即可全自动完成网络内核优化与全协议部署：

```bash
curl -fsSL [https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh](https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh) -o /tmp/suoha.sh && bash /tmp/suoha.sh

```

如果系统未预装 `curl`（如精简版 Debian / Ubuntu / Alpine），可使用 `wget` 代替：

```bash
wget -qO /tmp/suoha.sh [https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh](https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh) && bash /tmp/suoha.sh

```

部署完成后，所有内核调优状态、节点链接、Snell 配置及客户端订阅信息均保存在 `/opt/suoha_quick/v2ray.txt`，随时可通过以下命令再次查看：

```bash
cat /opt/suoha_quick/v2ray.txt

```

---

## 支持协议一览

| 协议类型 | 传输层 / 伪装特性 | 适用场景 |
| --- | --- | --- |
| **VLESS-Reality-Vision** | TCP + `xtls-rprx-vision` + Reality (`www.bing.com`) | 晚高峰主力直连、4K 秒开、高抗封锁 |
| **VLESS-Reality-gRPC** | gRPC (`gun`) + Reality (`www.bing.com`) | 适配需要多路复用或特定网络环境的客户端 |
| **AnyTLS** | TLS (`www.bing.com` 自签) + 动态 Padding 策略 | 新一代抗特征检测协议，适配 Mihomo / Sing-box |
| **Hysteria2** | QUIC + `h3` + TLS (`www.bing.com` 自签) | 高丢包、跨洲际长距离物理链路 4K 提速 |
| **TUIC v5** | QUIC + BBR + Native UDP Relay | 低延迟 UDP 转发、游戏与实时音视频 |
| **Snell v4** | 原生 Snell v4 (`ipv6 = true`，独立输出 v4/v6) | Surge、Clash Verge Rev、Mihomo 专属协议 |
| **Shadowsocks** | `aes-128-gcm` (双栈监听，IPv6 节点输出) | 轻量级原生加密、纯 IPv6 线路直连备用 |
| **VLESS-Argo** | WebSocket + 443 TLS (默认域名 + 双优选域名) | 宿主机 IP 被阻断时的应急兜底与 CDN 加速 |
| **Trojan-Argo** | WebSocket + 443 TLS (默认域名 + 双优选域名) | 复用同一条 Argo 隧道，提供双协议冗余备份 |

---

## 节点与订阅导入说明

| 导入目标 | 说明 | 示例格式 / 路径 |
| --- | --- | --- |
| **通用订阅 (v2rayN / NekoBox / Shadowrocket / Karing)** | 复制输出的通用订阅 URL 直接粘贴添加订阅 | `http://<VPS_IP>:<固定端口>/sub.txt` |
| **应用协议快速导入** | 复制并导入 `sub://` 深度链接快速调起客户端 | `sub://http://<VPS_IP>:<固定端口>/sub.txt` |
| **Clash Verge Rev / Mihomo 一键配置** | 在浏览器中打开或导入配置链接直接拉取策略组 | `clash://install-config?url=http://<VPS_IP>:<固定端口>/clash.yaml` |
| **Clash / Mihomo 原始配置文件直链** | 浏览器直接下载或作为远程配置链接输入 | `http://<VPS_IP>:<固定端口>/clash.yaml` |
| **Snell 双栈专属配置** | 终端直接输出标准 Surge 节点格式，同步写入 `clash.yaml` | `节点名 = snell, <IP>, <端口>, psk=..., version=4, reuse=true` |
| **单节点手动导入** | 支持独立复制导入各类通用 URI 链接 | `vless://...`、`trojan://...`、`anytls://...`、`hysteria2://...`、`tuic://...`、`ss://...` |

> **提示**：
> * **AnyTLS**、**Hysteria2** 与 **TUIC v5** 节点使用脚本自动签发的 `www.bing.com` 自签名证书，生成的链接与 YAML 配置中已默认附加跳过证书验证参数（`insecure=1` / `skip-cert-verify: true`），客户端直接导入即可使用。
> * Argo 节点默认的 `443` 端口可根据实际网络环境手动替换为 Cloudflare 支持的其他 TLS 端口（`2053`、`2083`、`2087`、`2096`、`8443`）。
> * 若使用带有外部防火墙/安全组的云服务商（如 AWS、Oracle Cloud、阿里云、腾讯云、GCP），请在控制台安全组放行对应随机端口（或全放行入站 TCP/UDP 流量）；Argo 隧道节点不受入站端口限制。
> 
> 

### 本地持久化文件结构

* **持久订阅目录**：`/var/www/suoha_sub/`
* `nodes.txt`：当前所有可用节点的明文 URI 连接串
* `sub.txt`：Base64 编码的通用客户端订阅源
* `clash.yaml`：适用于 Clash Verge Rev / Mihomo 的完整策略组配置文件（已启用 `ipv6: true`）
* `surge.conf`：适用于 Surge 的 Snell v4 双栈节点配置片段


* **内核网络调优配置**：`/etc/sysctl.d/99-suoha-4k.conf`
* **固定订阅端口记录**：`/etc/suoha_sub_port`
* **运行主目录**：`/opt/suoha_quick/`
* `sing-box` & `singbox.json`：官方 Sing-box 主力二进制文件与全协议配置文件
* `cloudflared-linux`：Cloudflare Argo 隧道组件
* `argo_router.py`：本地轻量级异步 WebSocket 路径分流守护脚本
* `snell-server` & `snell.conf`：官方 Snell v4 双栈服务端与配置文件
* `cert/bing.crt` & `cert/bing.key`：自动签发的 `www.bing.com` TLS 证书与私钥
* `v2ray.txt`：完整的节点信息、参数说明与客户端导入链接汇总



---

## 卸载与清理

执行以下任意一条卸载命令，脚本将自动终止所有运行中的 `sing-box`、`cloudflared-linux`、`snell-server`、本地分流器及后台 HTTP 订阅服务进程，还原内核网络参数配置，并彻底删除 `/opt/suoha_quick`、`/var/www/suoha_sub` 与 `/etc/suoha_sub_port`：

```bash
curl -fsSL [https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh](https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh) -o /tmp/suoha.sh && bash /tmp/suoha.sh uninstall

```

或者使用 `wget`：

```bash
wget -qO /tmp/suoha.sh [https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh](https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh) && bash /tmp/suoha.sh uninstall

```

---

## 免责声明

本脚本仅供技术研究、网络运维测试及协议学习使用。使用者请严格遵守当地法律法规，切勿用于任何违反法律或危害网络安全的行为。

```
