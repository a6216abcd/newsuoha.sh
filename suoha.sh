#!/bin/bash
# onekey suoha - Full Protocol Edition (官方Sing-box主力 + 单Argo双路径 + Reality[Vision/gRPC] + AnyTLS + HY2 + TUIC + Snell双栈 + SS-IPv6)

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

ACTION="${1:-install}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function show_progress() {
    local pct=$1
    local msg="$2"
    local width=32
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar_filled=""
    local bar_empty=""

    if [ $filled -gt 0 ]; then
        bar_filled=$(printf "%${filled}s" | tr ' ' '=')
    fi
    if [ $empty -gt 0 ]; then
        bar_empty=$(printf "%${empty}s" | tr ' ' '.')
    fi

    printf "\r\033[K${CYAN}[${GREEN}${bar_filled}${NC}${bar_empty}${CYAN}] ${YELLOW}%3d%%${NC} - %s" "$pct" "$msg"
}

linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0
OS_NAME=$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')

for i in "${linux_os[@]}"; do
    if [ "$i" == "$OS_NAME" ]; then
        break
    else
        n=$((n+1))
    fi
done

if [ $n -eq 5 ]; then
    n=0
fi

install_deps() {
    local deps=("unzip" "curl" "python3" "openssl" "tar" "jq")
    local need_update=0
    for dep in "${deps[@]}"; do
        if [ -z "$(type -P "$dep")" ]; then
            need_update=1
            break
        fi
    done

    if [ $need_update -eq 1 ]; then
        show_progress 4 "正在更新系统软件源..."
        ${linux_update[$n]} >/dev/null 2>&1
        local total_deps=${#deps[@]}
        local idx=0
        for dep in "${deps[@]}"; do
            idx=$((idx+1))
            local step_pct=$((4 + idx * 8 / total_deps))
            if [ -z "$(type -P "$dep")" ]; then
                show_progress $step_pct "正在安装依赖组件: ${dep}..."
                ${linux_install[$n]} "$dep" >/dev/null 2>&1
            fi
        done
    fi
    show_progress 12 "系统基础依赖检查完成"
}

function get_server_ip() {
    local ip=""
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [[ -z "$ip" || "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
        ip=$(curl -s4 --connect-timeout 3 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/ip/{print $2}')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s4 --connect-timeout 3 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\n\r ')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s4 --connect-timeout 3 https://api.ip.sb/ip 2>/dev/null | tr -d '\n\r ')
    fi
    echo "$ip"
}

function get_server_ipv6() {
    local ip6=""
    ip6=$(curl -s6 --connect-timeout 3 https://api64.ipify.org 2>/dev/null | tr -d '\n\r ')
    if [ -z "$ip6" ]; then
        ip6=$(curl -s6 --connect-timeout 3 https://ipv6.icanhazip.com 2>/dev/null | tr -d '\n\r ')
    fi
    if [ -z "$ip6" ]; then
        ip6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n 1 | tr -d '\n\r ')
    fi
    echo "$ip6"
}

function open_firewall_port() {
    local port="$1"
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw allow "${port}/tcp" >/dev/null 2>&1
            ufw allow "${port}/udp" >/dev/null 2>&1
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            firewall-cmd --zone=public --add-port="${port}/tcp" >/dev/null 2>&1
            firewall-cmd --zone=public --add-port="${port}/udp" >/dev/null 2>&1
        fi
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1
        iptables -C INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null || ip6tables -I INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1
        ip6tables -C INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null || ip6tables -I INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1
    fi
}

function get_or_create_sub_port() {
    local port_file="/etc/suoha_sub_port"
    local port=""
    if [ -f "$port_file" ]; then
        port=$(cat "$port_file" | tr -d '\n\r ')
    fi
    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        port=$((RANDOM%10000+25000))
        echo "$port" > "$port_file"
    fi
    open_firewall_port "$port"
    echo "$port"
}

function safe_kill_pidfile() {
    local pid_file="$1"
    if [ -f "$pid_file" ]; then
        local target_pid
        target_pid=$(tr -d ' \n\r' < "$pid_file")
        if [[ "$target_pid" =~ ^[0-9]+$ ]] && [ "$target_pid" != "$$" ] && [ "$target_pid" != "$PPID" ]; then
            kill -9 "$target_pid" >/dev/null 2>&1
        fi
        rm -f "$pid_file"
    fi
}

function start_sub_server() {
    local web_dir="$1"
    local port="$2"

    safe_kill_pidfile "/opt/suoha_quick/sub_http.pid"
    if command -v fuser >/dev/null 2>&1; then
        fuser -k "${port}/tcp" >/dev/null 2>&1
    fi
    sleep 0.3

    if [ -x "$(command -v python3)" ]; then
        nohup python3 -m http.server "$port" --bind :: --directory "$web_dir" >/dev/null 2>&1 &
        echo $! > /opt/suoha_quick/sub_http.pid
    fi
}

function sync_to_static_web() {
    local src_dir="$1"
    local static_dir="/var/www/suoha_sub"
    rm -rf "$static_dir" >/dev/null 2>&1
    mkdir -p "$static_dir" >/dev/null 2>&1
    [ -f "${src_dir}/nodes.txt" ] && cp -f "${src_dir}/nodes.txt" "${static_dir}/nodes.txt" 2>/dev/null
    [ -f "${src_dir}/sub.txt" ] && cp -f "${src_dir}/sub.txt" "${static_dir}/sub.txt" 2>/dev/null
    [ -f "${src_dir}/clash.yaml" ] && cp -f "${src_dir}/clash.yaml" "${static_dir}/clash.yaml" 2>/dev/null
    [ -f "${src_dir}/surge.conf" ] && cp -f "${src_dir}/surge.conf" "${static_dir}/surge.conf" 2>/dev/null
}

function stop_all_services() {
    safe_kill_pidfile "/opt/suoha_quick/singbox.pid"
    safe_kill_pidfile "/opt/suoha_quick/cf_main.pid"
    safe_kill_pidfile "/opt/suoha_quick/cf_vl.pid"
    safe_kill_pidfile "/opt/suoha_quick/cf_tr.pid"
    safe_kill_pidfile "/opt/suoha_quick/argo_router.pid"
    safe_kill_pidfile "/opt/suoha_quick/snell.pid"
    safe_kill_pidfile "/opt/suoha_quick/snell_v6.pid"
    safe_kill_pidfile "/opt/suoha_quick/sub_http.pid"

    if command -v killall >/dev/null 2>&1; then
        killall -9 sing-box cloudflared-linux snell-server snell-server-v6 >/dev/null 2>&1
    else
        for bin_name in sing-box cloudflared-linux snell-server snell-server-v6; do
            for pid in $(pidof "$bin_name" 2>/dev/null); do
                if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
                    kill -9 "$pid" >/dev/null 2>&1
                fi
            done
        done
    fi
}

function uninstall_all() {
    show_progress 20 "正在停止运行中的全协议代理进程..."
    stop_all_services
    sleep 0.5
    show_progress 60 "正在清理 HTTP 订阅守护进程..."
    if [ -f "/etc/suoha_sub_port" ]; then
        local old_port
        old_port=$(tr -d ' \n\r' < /etc/suoha_sub_port)
        if [[ "$old_port" =~ ^[0-9]+$ ]] && command -v fuser >/dev/null 2>&1; then
            fuser -k "${old_port}/tcp" >/dev/null 2>&1
        fi
    fi
    sleep 0.5
    show_progress 90 "正在删除配置文件与证书目录..."
    rm -rf /opt/suoha /opt/suoha_quick /etc/suoha_sub_port /var/www/suoha_sub /usr/bin/suoha
    show_progress 100 "卸载清理完成！"
    echo -e "\n所有梭哈全协议服务及订阅文件已彻底清理完成。"
    exit 0
}

if [ "$ACTION" == "uninstall" ]; then
    uninstall_all
fi

function quicktunnel_all_in_one() {
    clear
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${GREEN}   一键全协议梭哈部署启动中 (官方Sing-box主力 + 单Argo + Snell + SS-IPv6)${NC}"
    echo -e "${CYAN}==================================================================${NC}\n"

    show_progress 1 "初始化运行环境并彻底清空旧进程与历史文件..."
    stop_all_services
    install_deps

    rm -rf /opt/suoha /opt/suoha_quick /var/www/suoha_sub
    mkdir -p /opt/suoha_quick/cert >/dev/null 2>&1
    cd /opt/suoha_quick || exit 1

    # 1. 架构识别与核心下载
    local arch_sb=""
    local arch_cf=""
    local arch_snell=""

    case "$(uname -m)" in
        x86_64 | x64 | amd64 )
            arch_sb="linux-amd64"
            arch_cf="linux-amd64"
            arch_snell="linux-amd64"
            ;;
        i386 | i686 )
            arch_sb="linux-386"
            arch_cf="linux-386"
            arch_snell="linux-i386"
            ;;
        armv8 | arm64 | aarch64 )
            arch_sb="linux-arm64"
            arch_cf="linux-arm64"
            arch_snell="linux-aarch64"
            ;;
        armv7l )
            arch_sb="linux-armv7"
            arch_cf="linux-arm"
            arch_snell="linux-armv7l"
            ;;
        * )
            echo -e "\n${RED}当前架构 $(uname -m) 暂不支持！${NC}"
            exit 1
            ;;
    esac

    show_progress 15 "正在获取官方 Sing-box 稳定版核心..."
    local sb_version
    sb_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$sb_version" ]; then
        sb_version="1.12.12"
    fi

    show_progress 22 "正在下载官方 Sing-box v${sb_version} 主力核心..."
    curl -sL "https://github.com/SagerNet/sing-box/releases/download/v${sb_version}/sing-box-${sb_version}-${arch_sb}.tar.gz" -o sb.tar.gz
    tar -xzf sb.tar.gz >/dev/null 2>&1
    mv "sing-box-${sb_version}-${arch_sb}/sing-box" /opt/suoha_quick/sing-box 2>/dev/null
    rm -rf "sing-box-${sb_version}-${arch_sb}" sb.tar.gz

    show_progress 34 "正在下载 Cloudflare Argo 隧道组件..."
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${arch_cf}" -o /opt/suoha_quick/cloudflared-linux

    show_progress 44 "正在下载官方 Snell v4.1.1 双栈服务端..."
    curl -sL "https://dl.nssurge.com/snell/snell-server-v4.1.1-${arch_snell}.zip" -o snell.zip
    if [ -s snell.zip ] && unzip -t snell.zip >/dev/null 2>&1; then
        unzip -oq snell.zip -d /opt/suoha_quick/ >/dev/null 2>&1
    fi
    rm -f snell.zip

    chmod +x /opt/suoha_quick/sing-box /opt/suoha_quick/cloudflared-linux 2>/dev/null
    [ -f /opt/suoha_quick/snell-server ] && chmod +x /opt/suoha_quick/snell-server

    if [ ! -x /opt/suoha_quick/sing-box ] || [ ! -x /opt/suoha_quick/cloudflared-linux ]; then
        echo -e "\n${RED}核心文件下载失败，请检查服务器网络连接（GitHub 访问是否正常）！${NC}"
        exit 1
    fi

    # 2. 探测服务器公网 IPv4 与 IPv6
    show_progress 48 "正在探测服务器双栈公网 IP..."
    local server_ip
    server_ip=$(get_server_ip)
    local server_ipv6
    server_ipv6=$(get_server_ipv6)

    # 3. 生成自签名 swdist.apple.com 证书与 Reality X25519 密钥 (Reality 保留 www.bing.com)
    show_progress 52 "正在自签 swdist.apple.com TLS 证书与 Reality X25519 密钥..."
    openssl ecparam -genkey -name prime256v1 -out /opt/suoha_quick/cert/apple.key >/dev/null 2>&1
    openssl req -new -x509 -days 3650 -key /opt/suoha_quick/cert/apple.key \
        -out /opt/suoha_quick/cert/apple.crt \
        -subj "/C=US/ST=California/L=Cupertino/O=Apple Inc./CN=swdist.apple.com" \
        -addext "subjectAltName=DNS:swdist.apple.com,DNS:apple.com" >/dev/null 2>&1

    local reality_keys
    reality_keys=$(/opt/suoha_quick/sing-box generate reality-keypair)
    local reality_priv
    reality_priv=$(echo "$reality_keys" | awk '/PrivateKey:/ {print $2}')
    local reality_pub
    reality_pub=$(echo "$reality_keys" | awk '/PublicKey:/ {print $2}')
    local reality_sid
    reality_sid=$(openssl rand -hex 8)

    # 4. 分配随机端口与凭证
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local short_id
    short_id=$(echo "$uuid" | awk -F- '{print $1}')
    local urlpath_vless="vl-${short_id}"
    local urlpath_trojan="tr-${short_id}"
    local grpc_service="gr-${short_id}"
    local password_all
    password_all=$(openssl rand -hex 12)
    local ss_method="aes-128-gcm"
    local ss_password
    ss_password=$(openssl rand -hex 12)

    local port_argo_entry=$((RANDOM%10000+11000))
    local port_argo_vl=$((port_argo_entry+1))
    local port_argo_tr=$((port_argo_entry+2))
    local port_reality=$((RANDOM%10000+21000))
    local port_anytls=$((port_reality+1))
    local port_hy2=$((port_reality+2))
    local port_tuic=$((port_reality+3))
    local port_snell=$((port_reality+4))
    local port_ss_v6=$((port_reality+5))
    local port_rel_grpc=$((port_reality+6))

    open_firewall_port "$port_reality"
    open_firewall_port "$port_rel_grpc"
    open_firewall_port "$port_anytls"
    open_firewall_port "$port_hy2"
    open_firewall_port "$port_tuic"
    open_firewall_port "$port_snell"
    open_firewall_port "$port_ss_v6"

    # 5. 生成官方 Sing-box 主力全协议配置文件 (已暂时屏蔽/移除 XHTTP 节点)
    show_progress 58 "正在写入官方 Sing-box 主力全协议配置..."
    cat > /opt/suoha_quick/singbox.json <<EOF
{
  "log": {
    "level": "error",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "argo-vless-in",
      "listen": "127.0.0.1",
      "listen_port": ${port_argo_vl},
      "users": [
        {
          "uuid": "${uuid}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${urlpath_vless}"
      }
    },
    {
      "type": "trojan",
      "tag": "argo-trojan-in",
      "listen": "127.0.0.1",
      "listen_port": ${port_argo_tr},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${urlpath_trojan}"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${port_reality},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.bing.com",
            "server_port": 443
          },
          "private_key": "${reality_priv}",
          "short_id": [
            "${reality_sid}"
          ]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-grpc-in",
      "listen": "::",
      "listen_port": ${port_rel_grpc},
      "users": [
        {
          "uuid": "${uuid}"
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "${grpc_service}"
      },
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.bing.com",
            "server_port": 443
          },
          "private_key": "${reality_priv}",
          "short_id": [
            "${reality_sid}"
          ]
        }
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${port_anytls},
      "users": [
        {
          "password": "${password_all}"
        }
      ],
      "padding_scheme": [
        "stop=8",
        "0=30-30",
        "1=100-400",
        "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
        "3=9-9,500-1000",
        "4=500-1000",
        "5=500-1000",
        "6=500-1000",
        "7=500-1000"
      ],
      "tls": {
        "enabled": true,
        "server_name": "swdist.apple.com",
        "certificate_path": "/opt/suoha_quick/cert/apple.crt",
        "key_path": "/opt/suoha_quick/cert/apple.key"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${password_all}"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "/opt/suoha_quick/cert/apple.crt",
        "key_path": "/opt/suoha_quick/cert/apple.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": ${port_tuic},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${password_all}"
        }
      ],
      "congestion_control": "bbr",
      "zero_rtt_handshake": false,
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "/opt/suoha_quick/cert/apple.crt",
        "key_path": "/opt/suoha_quick/cert/apple.key"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-ipv6-in",
      "listen": "::",
      "listen_port": ${port_ss_v6},
      "method": "${ss_method}",
      "password": "${ss_password}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    show_progress 66 "正在启动官方 Sing-box 主力、本地分流器与 Snell 双栈守护进程..."
    nohup /opt/suoha_quick/sing-box run -c /opt/suoha_quick/singbox.json >/opt/suoha_quick/singbox.log 2>&1 &
    local sb_pid=$!
    echo $sb_pid > /opt/suoha_quick/singbox.pid

    # 轻量本地 WebSocket 路径分流守护进程 (单 Argo 域名按请求路径分发 /vl-xxx 与 /tr-xxx)
    cat > /opt/suoha_quick/argo_router.py <<EOF
import asyncio

async def relay(reader, writer):
    try:
        while True:
            chunk = await reader.read(32768)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

async def handle_client(client_reader, client_writer):
    try:
        head = await asyncio.wait_for(client_reader.readuntil(b"\r\n\r\n"), timeout=10.0)
        first_line = head.split(b"\r\n", 1)[0]
        target_port = ${port_argo_vl}
        if b"/${urlpath_trojan}" in first_line:
            target_port = ${port_argo_tr}
        upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", target_port)
        upstream_writer.write(head)
        await upstream_writer.drain()
        await asyncio.gather(
            relay(client_reader, upstream_writer),
            relay(upstream_reader, client_writer)
        )
    except Exception:
        try:
            client_writer.close()
        except Exception:
            pass

async def main():
    server = await asyncio.start_server(handle_client, "127.0.0.1", ${port_argo_entry})
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
EOF
    nohup python3 /opt/suoha_quick/argo_router.py >/dev/null 2>&1 &
    echo $! > /opt/suoha_quick/argo_router.pid

    # 启动 Snell 双栈监听 (使用 ::0:端口 语法确保 IPv4 + IPv6 同步监听)
    local snell_psk
    snell_psk=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    local snell_installed=0
    local snell_status="未安装"

    if [ -x /opt/suoha_quick/snell-server ]; then
        cat > /opt/suoha_quick/snell.conf <<EOF
[snell-server]
listen = ::0:${port_snell}
psk = ${snell_psk}
ipv6 = true
obfs = off
EOF
        nohup /opt/suoha_quick/snell-server -c /opt/suoha_quick/snell.conf >/opt/suoha_quick/snell.log 2>&1 &
        local snell_pid=$!
        echo $snell_pid > /opt/suoha_quick/snell.pid
        sleep 0.5
        if ! kill -0 "$snell_pid" 2>/dev/null; then
            sed -i "s|::0|0.0.0.0|g" /opt/suoha_quick/snell.conf
            nohup /opt/suoha_quick/snell-server -c /opt/suoha_quick/snell.conf >/opt/suoha_quick/snell.log 2>&1 &
            snell_pid=$!
            echo $snell_pid > /opt/suoha_quick/snell.pid
            sleep 0.5
        fi
        if kill -0 "$snell_pid" 2>/dev/null; then
            snell_installed=1
            local listen_info
            listen_info=$(ss -tlpn 2>/dev/null | grep "pid=${snell_pid}" | awk '{print $4}' | tr '\n' ' ')
            snell_status="运行正常 (PID:${snell_pid} | 监听:${listen_info:-::0:${port_snell}})"
        fi
    fi

    local sb_status="运行正常 (PID:${sb_pid})"
    if ! kill -0 "$sb_pid" 2>/dev/null; then
        sb_status="异常: $(cat /opt/suoha_quick/singbox.log 2>/dev/null | tr '\n' ' ')"
    fi

    # 6. 拉起单个 Cloudflare Argo 隧道 (双协议共用同一 Argo 域名)
    show_progress 70 "正在获取机房归属并建立单 Argo 双路径隧道..."
    local ips=4
    if [ -z "$server_ip" ] && [ -n "$server_ipv6" ]; then
        ips=6
    fi

    local isp
    isp=$(curl -${ips} -s --connect-timeout 3 https://speed.cloudflare.com/meta 2>/dev/null | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
    local node_tag
    node_tag=$(echo "$isp" | sed -e 's/_/%20/g' -e 's/,/%2C/g')
    if [[ -z "$node_tag" || "$node_tag" == "--" || "$node_tag" == "-" ]]; then
        node_tag="Suoha_Node"
    fi

    show_progress 74 "正在申请 Argo 隧道 (VLESS /${urlpath_vless} + Trojan /${urlpath_trojan})..."
    /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_entry}" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > /opt/suoha_quick/argo_main.log 2>&1 &
    echo $! > /opt/suoha_quick/cf_main.pid

    local wait_sec=0
    local argo_domain=""
    while true; do
        wait_sec=$((wait_sec+1))
        argo_domain=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" /opt/suoha_quick/argo_main.log 2>/dev/null | head -n 1 | awk -F// '{print $2}')

        if [ -n "$argo_domain" ]; then
            rm -f /opt/suoha_quick/argo_main.log
            show_progress 92 "Argo 单域名双路径隧道分配成功: ${argo_domain}"
            break
        fi

        local dynamic_pct=$((74 + wait_sec))
        if [ $dynamic_pct -gt 91 ]; then
            dynamic_pct=91
        fi
        show_progress $dynamic_pct "等待 Argo 分配双协议共用域名 [${wait_sec}s]..."

        if [ $wait_sec -ge 25 ]; then
            wait_sec=0
            safe_kill_pidfile "/opt/suoha_quick/cf_main.pid"
            rm -f /opt/suoha_quick/argo_main.log
            show_progress 75 "Argo 获取超时，正在自动切换 QUIC 重连建立隧道..."
            /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_entry}" --no-autoupdate --edge-ip-version "$ips" --protocol quic > /opt/suoha_quick/argo_main.log 2>&1 &
            echo $! > /opt/suoha_quick/cf_main.pid
            sleep 2
        else
            sleep 1
        fi
    done

    # 7. 生成全协议节点链接与 Clash / Mihomo 配置文件
    show_progress 95 "正在生成全协议 URI 链接与 Clash/Mihomo 聚合配置..."
    > /opt/suoha_quick/nodes.txt
    > /opt/suoha_quick/surge.conf

    cat > /opt/suoha_quick/clash.yaml <<EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
ipv6: true
proxies:
EOF

    local proxy_names=()
    local opt_domains=("cf.090227.xyz" "cloudflare.182682.xyz")
    local opt_labels=("优选cf.090227" "优选182682")

    local argo_domains=("$argo_domain" "${opt_domains[@]}")
    local argo_labels=("默认Argo" "${opt_labels[@]}")

    # (A) VLESS Argo 节点组
    for idx in "${!argo_domains[@]}"; do
        local d="${argo_domains[$idx]}"
        local l="${argo_labels[$idx]}"
        local pname="${node_tag}-VLESS-${l}-443"
        echo "vless://${uuid}@${d}:443?encryption=none&security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2F${urlpath_vless}#${pname}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname}"
    type: vless
    server: ${d}
    port: 443
    uuid: ${uuid}
    cipher: auto
    tls: true
    udp: true
    servername: ${argo_domain}
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${argo_domain}
EOF
    done

    # (B) Trojan Argo 节点组
    for idx in "${!argo_domains[@]}"; do
        local d="${argo_domains[$idx]}"
        local l="${argo_labels[$idx]}"
        local pname="${node_tag}-Trojan-${l}-443"
        echo "trojan://${uuid}@${d}:443?security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2F${urlpath_trojan}#${pname}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname}"
    type: trojan
    server: ${d}
    port: 443
    password: ${uuid}
    udp: true
    sni: ${argo_domain}
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${argo_domain}
EOF
    done

    # 确定直连连接地址
    local direct_host=""
    local direct_yaml_host=""
    if [ -n "$server_ip" ]; then
        direct_host="$server_ip"
        direct_yaml_host="$server_ip"
    elif [ -n "$server_ipv6" ]; then
        direct_host="[${server_ipv6}]"
        direct_yaml_host="$server_ipv6"
    fi

    if [ -n "$direct_host" ]; then
        # (C1) VLESS Reality Vision 直连节点 (主力首选 - 保留 www.bing.com)
        local pname_rel="${node_tag}-VLESS-Reality-Vision"
        echo "vless://${uuid}@${direct_host}:${port_reality}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.bing.com&fp=chrome&pbk=${reality_pub}&sid=${reality_sid}&type=tcp&headerType=none#${pname_rel}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_rel")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_rel}"
    type: vless
    server: ${direct_yaml_host}
    port: ${port_reality}
    uuid: ${uuid}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.bing.com
    reality-opts:
      public-key: ${reality_pub}
      short-id: ${reality_sid}
      client-fingerprint: chrome
EOF

        # (C2) VLESS Reality gRPC 直连节点 (保留 www.bing.com)
        local pname_rel_grpc="${node_tag}-VLESS-Reality-gRPC"
        echo "vless://${uuid}@${direct_host}:${port_rel_grpc}?encryption=none&security=reality&sni=www.bing.com&fp=chrome&pbk=${reality_pub}&sid=${reality_sid}&type=grpc&serviceName=${grpc_service}&mode=gun#${pname_rel_grpc}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_rel_grpc")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_rel_grpc}"
    type: vless
    server: ${direct_yaml_host}
    port: ${port_rel_grpc}
    uuid: ${uuid}
    network: grpc
    tls: true
    udp: true
    servername: www.bing.com
    grpc-opts:
      grpc-service-name: ${grpc_service}
    reality-opts:
      public-key: ${reality_pub}
      short-id: ${reality_sid}
      client-fingerprint: chrome
EOF

        # (D) AnyTLS 直连节点 (自签 swdist.apple.com)
        local pname_any="${node_tag}-AnyTLS-Apple"
        echo "anytls://${password_all}@${direct_host}:${port_anytls}?sni=swdist.apple.com&insecure=1#${pname_any}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_any")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_any}"
    type: anytls
    server: ${direct_yaml_host}
    port: ${port_anytls}
    password: "${password_all}"
    client-fingerprint: chrome
    udp: true
    sni: swdist.apple.com
    skip-cert-verify: true
EOF

        # (E) Hysteria2 直连节点 (自签 swdist.apple.com)
        local pname_hy2="${node_tag}-Hysteria2-Apple"
        echo "hysteria2://${password_all}@${direct_host}:${port_hy2}?sni=swdist.apple.com&insecure=1#${pname_hy2}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_hy2")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_hy2}"
    type: hysteria2
    server: ${direct_yaml_host}
    port: ${port_hy2}
    password: "${password_all}"
    sni: swdist.apple.com
    skip-cert-verify: true
    alpn:
      - h3
EOF

        # (F) TUIC v5 直连节点 (自签 swdist.apple.com)
        local pname_tuic="${node_tag}-TUICv5-Apple"
        echo "tuic://${uuid}:${password_all}@${direct_host}:${port_tuic}?congestion_control=bbr&alpn=h3&sni=swdist.apple.com&udp_relay_mode=native&allow_insecure=1#${pname_tuic}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_tuic")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_tuic}"
    type: tuic
    server: ${direct_yaml_host}
    port: ${port_tuic}
    uuid: ${uuid}
    password: "${password_all}"
    alpn:
      - h3
    disable-sni: false
    reduce-rtt: true
    udp-relay-mode: native
    congestion-controller: bbr
    sni: swdist.apple.com
    skip-cert-verify: true
EOF
    fi

    # (G) 原生 Shadowsocks IPv6 直连节点 (ss-ipv6)
    local ss_v6_uri=""
    if [ -n "$server_ipv6" ]; then
        local ss_user_info="${ss_method}:${ss_password}"
        local ss_base64=""
        if [ "$OS_NAME" == "Alpine" ]; then
            ss_base64=$(echo -n "$ss_user_info" | base64 | tr -d '\n')
        else
            ss_base64=$(echo -n "$ss_user_info" | base64 -w 0)
        fi
        local pname_ss6="${node_tag}-SS-IPv6"
        ss_v6_uri="ss://${ss_base64}@[${server_ipv6}]:${port_ss_v6}#${pname_ss6}"
        echo "$ss_v6_uri" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_ss6")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_ss6}"
    type: ss
    server: "${server_ipv6}"
    port: ${port_ss_v6}
    cipher: ${ss_method}
    password: "${ss_password}"
    udp: true
EOF
    fi

    # (H) Snell 双栈节点
    local snell_display_lines=""
    if [ $snell_installed -eq 1 ]; then
        if [ -n "$server_ip" ]; then
            local pname_snell_v4="${node_tag}-Snell-IPv4"
            proxy_names+=("$pname_snell_v4")
            cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_snell_v4}"
    type: snell
    server: ${server_ip}
    port: ${port_snell}
    psk: "${snell_psk}"
    version: 4
    udp: true
EOF
            local surge_v4="${pname_snell_v4} = snell, ${server_ip}, ${port_snell}, psk=${snell_psk}, version=4, reuse=true"
            echo "$surge_v4" >> /opt/suoha_quick/surge.conf
            snell_display_lines+="${surge_v4}\n"
        fi

        if [ -n "$server_ipv6" ]; then
            local pname_snell_v6="${node_tag}-Snell-IPv6"
            proxy_names+=("$pname_snell_v6")
            cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_snell_v6}"
    type: snell
    ip-version: ipv6
    server: "${server_ipv6}"
    port: ${port_snell}
    psk: "${snell_psk}"
    version: 4
    udp: true
EOF
            local surge_v6="${pname_snell_v6} = snell, ${server_ipv6}, ${port_snell}, psk=${snell_psk}, version=4, reuse=true"
            echo "$surge_v6" >> /opt/suoha_quick/surge.conf
            snell_display_lines+="${surge_v6}\n"
        fi
    fi

    cat >> /opt/suoha_quick/clash.yaml <<EOF
proxy-groups:
  - name: PROXY
    type: select
    proxies:
EOF

    for pname in "${proxy_names[@]}"; do
        echo "      - \"${pname}\"" >> /opt/suoha_quick/clash.yaml
    done

    cat >> /opt/suoha_quick/clash.yaml <<EOF
rules:
  - MATCH,PROXY
EOF

    show_progress 98 "正在编码 Base64 订阅并拉起本地 HTTP 订阅服务..."
    if [ "$OS_NAME" == "Alpine" ]; then
        base64 /opt/suoha_quick/nodes.txt | tr -d '\n' > /opt/suoha_quick/sub.txt
    else
        base64 -w 0 /opt/suoha_quick/nodes.txt > /opt/suoha_quick/sub.txt
    fi

    local sub_host=""
    if [ -n "$server_ip" ]; then
        sub_host="$server_ip"
    elif [ -n "$server_ipv6" ]; then
        sub_host="[${server_ipv6}]"
    else
        sub_host="$argo_domain"
    fi

    local sub_port
    sub_port=$(get_or_create_sub_port)
    sync_to_static_web "/opt/suoha_quick"
    start_sub_server "/var/www/suoha_sub" "$sub_port"

    local sub_online_url="http://${sub_host}:${sub_port}/sub.txt"
    local clash_online_url="http://${sub_host}:${sub_port}/clash.yaml"

    cat > /opt/suoha_quick/v2ray.txt <<EOF
======================== 一键全协议梭哈节点列表 ========================
[核心运行状态]:
  ├─ 官方 Sing-box 主力进程 : ${sb_status}
  └─ Snell 双栈守护进程    : ${snell_status}

[单 Argo 共用域名]: ${argo_domain}
  ├─ VLESS  WebSocket 路径: /${urlpath_vless}
  └─ Trojan WebSocket 路径: /${urlpath_trojan}

[URI 通用节点链接 (Argo / Reality[Vision/gRPC] / AnyTLS / HY2 / TUIC / SS-IPv6)]
$(cat /opt/suoha_quick/nodes.txt)

[Snell 双栈专属配置 (Surge / Clash Verge / Mihomo)]
$(echo -e "${snell_display_lines:-未检测到可用公网 IP，跳过 Snell 生成}")
======================== 端口与证书说明 ========================
- Argo 节点 443 端口可按需替换为 CF 其它 TLS 端口: 2053, 2083, 2087, 2096, 8443

- AnyTLS / Hysteria2 / TUIC 均已自动签发 swdist.apple.com 证书 (客户端需开启跳过证书验证)

- VLESS Reality 共用参数 -> 伪装域名: www.bing.com | PublicKey: ${reality_pub} | ShortID: ${reality_sid}

  ├─ Reality Vision 端口: ${port_reality}
  └─ Reality gRPC   端口: ${port_rel_grpc} (ServiceName: ${grpc_service})
- (注: XHTTP 节点已暂时屏蔽，等待官方内核原生支持)


======================== 客户端订阅及导入链接 ========================
本机固定订阅服务端口: ${sub_port} (已永久保存，重新梭哈无需重新导入客户端)

1. 通用在线订阅链接 (v2rayN / NekoBox / Shadowrocket / Karing):

${sub_online_url}

2. v2rayN / NekoBox 一键导入链接:
sub://${sub_online_url}

3. Clash Verge Rev / Mihomo 一键导入配置:
clash://install-config?url=${clash_online_url}

4. Clash / Mihomo 在线 YAML 直链:
${clash_online_url}

快捷卸载命令: bash $(readlink -f "$0" 2>/dev/null || echo "$0") uninstall
=====================================================================
EOF

    show_progress 100 "全部协议部署完成！"
    sleep 0.6
    clear
    cat /opt/suoha_quick/v2ray.txt
    echo -e "\n所有配置已保存至 /opt/suoha_quick/v2ray.txt，随时执行 cat /opt/suoha_quick/v2ray.txt 查看。"
}

quicktunnel_all_in_one
