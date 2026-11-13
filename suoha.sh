#!/bin/bash
# onekey suoha - Full Protocol Edition (Argo + Reality[Vision/XHTTP/gRPC] + AnyTLS + HY2 + TUIC + Snell双栈 + SS-IPv6)

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
    echo "$ip6"
}

function is_port_free() {
    local p="$1"
    if ss -tulpn 2>/dev/null | grep -qE ":${p}\b"; then
        return 1
    fi
    return 0
}

function pick_preferred_port() {
    local candidates=("$@")
    for p in "${candidates[@]}"; do
        if is_port_free "$p"; then
            echo "$p"
            return
        fi
    done
    while true; do
        local rp=$((RANDOM%15000+20000))
        if is_port_free "$rp"; then
            echo "$rp"
            return
        fi
    done
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
        port=$(pick_preferred_port 8880 2052 2082 2086 2095)
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
    safe_kill_pidfile "/opt/suoha_quick/xray.pid"
    safe_kill_pidfile "/opt/suoha_quick/cf_vl.pid"
    safe_kill_pidfile "/opt/suoha_quick/cf_tr.pid"
    safe_kill_pidfile "/opt/suoha_quick/snell_v4.pid"
    safe_kill_pidfile "/opt/suoha_quick/snell_v6.pid"
    safe_kill_pidfile "/opt/suoha_quick/sub_http.pid"

    if command -v killall >/dev/null 2>&1; then
        killall -9 sing-box xray cloudflared-linux snell-server >/dev/null 2>&1
    else
        for bin_name in sing-box xray cloudflared-linux snell-server; do
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
    echo -e "${GREEN}   一键全协议梭哈部署启动中 (Argo + Reality三件套 + AnyTLS + HY2 + TUIC + Snell双栈 + SS-IPv6)${NC}"
    echo -e "${CYAN}==================================================================${NC}\n"

    show_progress 1 "初始化运行环境并清理旧进程..."
    stop_all_services
    install_deps

    rm -rf /opt/suoha_quick
    mkdir -p /opt/suoha_quick/cert >/dev/null 2>&1
    cd /opt/suoha_quick || exit 1

    # 1. 架构识别与核心二进制下载
    local arch_sb=""
    local arch_xray=""
    local arch_cf=""
    local arch_snell=""

    case "$(uname -m)" in
        x86_64 | x64 | amd64 )
            arch_sb="linux-amd64"
            arch_xray="Xray-linux-64.zip"
            arch_cf="linux-amd64"
            arch_snell="linux-amd64"
            ;;
        i386 | i686 )
            arch_sb="linux-386"
            arch_xray="Xray-linux-32.zip"
            arch_cf="linux-386"
            arch_snell="linux-i386"
            ;;
        armv8 | arm64 | aarch64 )
            arch_sb="linux-arm64"
            arch_xray="Xray-linux-arm64-v8a.zip"
            arch_cf="linux-arm64"
            arch_snell="linux-aarch64"
            ;;
        armv7l )
            arch_sb="linux-armv7"
            arch_xray="Xray-linux-arm32-v7a.zip"
            arch_cf="linux-arm"
            arch_snell="linux-armv7l"
            ;;
        * )
            echo -e "\n${RED}当前架构 $(uname -m) 暂不支持！${NC}"
            exit 1
            ;;
    esac

    show_progress 14 "正在获取最新 Sing-box 版本号..."
    local sb_version
    sb_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$sb_version" ]; then
        sb_version="1.12.12"
    fi

    show_progress 20 "正在下载 Sing-box v${sb_version} 核心..."
    curl -sL "https://github.com/SagerNet/sing-box/releases/download/v${sb_version}/sing-box-${sb_version}-${arch_sb}.tar.gz" -o sb.tar.gz
    tar -xzf sb.tar.gz >/dev/null 2>&1
    mv "sing-box-${sb_version}-${arch_sb}/sing-box" /opt/suoha_quick/sing-box 2>/dev/null
    rm -rf "sing-box-${sb_version}-${arch_sb}" sb.tar.gz

    show_progress 28 "正在下载最新 Xray-core 核心 (Reality Vision/XHTTP/gRPC)..."
    curl -sL "https://github.com/XTLS/Xray-core/releases/latest/download/${arch_xray}" -o xray.zip
    mkdir -p /opt/suoha_quick/tmp_xray
    unzip -oq xray.zip -d /opt/suoha_quick/tmp_xray >/dev/null 2>&1
    mv /opt/suoha_quick/tmp_xray/xray /opt/suoha_quick/xray 2>/dev/null
    rm -rf /opt/suoha_quick/tmp_xray xray.zip

    show_progress 36 "正在下载 Cloudflare Argo 隧道组件..."
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${arch_cf}" -o /opt/suoha_quick/cloudflared-linux

    show_progress 44 "正在下载官方 Snell v4.1.1 双栈服务端..."
    curl -sL "https://dl.nssurge.com/snell/snell-server-v4.1.1-${arch_snell}.zip" -o snell.zip
    if [ -s snell.zip ] && unzip -t snell.zip >/dev/null 2>&1; then
        unzip -oq snell.zip -d /opt/suoha_quick/ >/dev/null 2>&1
    fi
    rm -f snell.zip

    chmod +x /opt/suoha_quick/sing-box /opt/suoha_quick/xray /opt/suoha_quick/cloudflared-linux 2>/dev/null
    [ -f /opt/suoha_quick/snell-server ] && chmod +x /opt/suoha_quick/snell-server

    if [ ! -x /opt/suoha_quick/sing-box ] || [ ! -x /opt/suoha_quick/xray ] || [ ! -x /opt/suoha_quick/cloudflared-linux ]; then
        echo -e "\n${RED}核心文件下载失败，请检查服务器网络连接（GitHub 访问是否正常）！${NC}"
        exit 1
    fi

    # 2. 探测服务器公网 IPv4 与 真实可出站的 IPv6
    show_progress 48 "正在探测服务器双栈公网 IP 与出站连通性..."
    local server_ip
    server_ip=$(get_server_ip)
    local server_ipv6
    server_ipv6=$(get_server_ipv6)

    # 3. 生成自签名 www.bing.com 证书，使用 sing-box 生成标准的 43 位 X25519 密钥对 (Xray 与 Mihomo 通用标准格式)
    show_progress 52 "正在自签 TLS 证书与生成标准 Reality X25519 密钥对..."
    openssl ecparam -genkey -name prime256v1 -out /opt/suoha_quick/cert/bing.key >/dev/null 2>&1
    openssl req -new -x509 -days 3650 -key /opt/suoha_quick/cert/bing.key \
        -out /opt/suoha_quick/cert/bing.crt \
        -subj "/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/CN=www.bing.com" \
        -addext "subjectAltName=DNS:www.bing.com,DNS:bing.com" >/dev/null 2>&1

    local reality_keys
    reality_keys=$(/opt/suoha_quick/sing-box generate reality-keypair)
    local reality_priv
    reality_priv=$(echo "$reality_keys" | grep -i "PrivateKey" | cut -d':' -f2 | tr -d ' \r\n')
    local reality_pub
    reality_pub=$(echo "$reality_keys" | grep -i "PublicKey" | cut -d':' -f2 | tr -d ' \r\n')
    local reality_sid
    reality_sid=$(openssl rand -hex 8)

    # 选用全球全区域支持 TLS 1.3 + H2 + X25519 的微软官方域名作为 Reality 伪装目标
    local reality_sni="www.microsoft.com"

    # 4. 分配端口与凭证
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local short_id
    short_id=$(echo "$uuid" | awk -F- '{print $1}')
    local urlpath_vless="vl-${short_id}"
    local urlpath_trojan="tr-${short_id}"
    local xhttp_path="/xh-${short_id}"
    local grpc_service="gr-${short_id}"
    local password_all
    password_all=$(openssl rand -hex 12)
    local ss_method="aes-128-gcm"
    local ss_password
    ss_password=$(openssl rand -hex 12)

    local port_argo_vl=$((RANDOM%10000+11000))
    local port_argo_tr=$((port_argo_vl+1))
    local port_rel_vision
    port_rel_vision=$(pick_preferred_port 443 8443 2053 2083 2087 2096)
    local port_rel_xhttp
    port_rel_xhttp=$(pick_preferred_port 8443 2053 2083 2087 2096)
    local port_rel_grpc
    port_rel_grpc=$(pick_preferred_port 2053 2083 2087 2096 8443)
    local port_anytls
    port_anytls=$(pick_preferred_port 2083 2087 2096 8443)
    local port_hy2
    port_hy2=$(pick_preferred_port 2087 2096 8443)
    local port_tuic
    port_tuic=$(pick_preferred_port 2096 8443)
    local port_snell_v4=$((RANDOM%10000+31000))
    local port_snell_v6=$((port_snell_v4+1))
    local port_ss_v6=$((port_snell_v4+2))

    open_firewall_port "$port_rel_vision"
    open_firewall_port "$port_rel_xhttp"
    open_firewall_port "$port_rel_grpc"
    open_firewall_port "$port_anytls"
    open_firewall_port "$port_hy2"
    open_firewall_port "$port_tuic"
    open_firewall_port "$port_snell_v4"
    open_firewall_port "$port_snell_v6"
    open_firewall_port "$port_ss_v6"

    # 5. 生成 Xray 多入站 Reality 配置文件
    # 注意: Xray 25/26+ 中 network 可写 tcp 或 raw，此处使用 tcp 兼容全版本；xhttp 使用 auto 模式与 Mihomo 默认兼容
    show_progress 58 "正在写入 Xray Reality (Vision + XHTTP + gRPC) 三件套配置..."
    local xray_listen="0.0.0.0"
    if [ -z "$server_ip" ] && [ -n "$server_ipv6" ]; then
        xray_listen="::"
    fi

    cat > /opt/suoha_quick/xray.json <<EOF
{
  "log": {
    "loglevel": "error"
  },
  "inbounds": [
    {
      "tag": "reality-vision-in",
      "listen": "${xray_listen}",
      "port": ${port_rel_vision},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${reality_sni}:443",
          "xver": 0,
          "serverNames": [
            "${reality_sni}"
          ],
          "privateKey": "${reality_priv}",
          "shortIds": [
            "${reality_sid}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "tag": "reality-xhttp-in",
      "listen": "${xray_listen}",
      "port": ${port_rel_xhttp},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${xhttp_path}",
          "mode": "auto"
        },
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${reality_sni}:443",
          "xver": 0,
          "serverNames": [
            "${reality_sni}"
          ],
          "privateKey": "${reality_priv}",
          "shortIds": [
            "${reality_sid}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "tag": "reality-grpc-in",
      "listen": "${xray_listen}",
      "port": ${port_rel_grpc},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "${grpc_service}"
        },
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${reality_sni}:443",
          "xver": 0,
          "serverNames": [
            "${reality_sni}"
          ],
          "privateKey": "${reality_priv}",
          "shortIds": [
            "${reality_sid}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    # 6. 生成 Sing-box 配置文件 (负责 Argo WS + AnyTLS + Hysteria2 + TUIC v5 + SS-IPv6)
    show_progress 62 "正在写入 Sing-box (Argo + AnyTLS + HY2 + TUIC + SS-IPv6) 配置文件..."
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
        "server_name": "www.bing.com",
        "certificate_path": "/opt/suoha_quick/cert/bing.crt",
        "key_path": "/opt/suoha_quick/cert/bing.key"
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
        "certificate_path": "/opt/suoha_quick/cert/bing.crt",
        "key_path": "/opt/suoha_quick/cert/bing.key"
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
        "certificate_path": "/opt/suoha_quick/cert/bing.crt",
        "key_path": "/opt/suoha_quick/cert/bing.key"
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

    show_progress 66 "正在启动 Xray-core、Sing-box 与双栈 Snell 守护进程..."
    nohup /opt/suoha_quick/xray run -c /opt/suoha_quick/xray.json >/opt/suoha_quick/xray.log 2>&1 &
    local xray_pid=$!
    echo $xray_pid > /opt/suoha_quick/xray.pid

    nohup /opt/suoha_quick/sing-box run -c /opt/suoha_quick/singbox.json >/opt/suoha_quick/singbox.log 2>&1 &
    local sb_pid=$!
    echo $sb_pid > /opt/suoha_quick/singbox.pid

    sleep 1
    local xray_status=""
    if kill -0 "$xray_pid" 2>/dev/null; then
        local listening_ports
        listening_ports=$(ss -tulpn 2>/dev/null | grep "pid=${xray_pid}" | awk '{print $5}' | tr '\n' ' ')
        xray_status="运行正常 (PID:${xray_pid} | 监听:${listening_ports:-已就绪})"
    else
        xray_status="启动失败! 错误日志: $(cat /opt/suoha_quick/xray.log 2>/dev/null | tr '\n' ' ')"
    fi

    # 启动独立 IPv4 与 IPv6 双 Snell 实例
    local snell_psk
    snell_psk=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    local snell_v4_ok=0
    local snell_v6_ok=0
    local snell_status=""

    if [ -x /opt/suoha_quick/snell-server ]; then
        if [ -n "$server_ip" ]; then
            cat > /opt/suoha_quick/snell_v4.conf <<EOF
[snell-server]
listen = 0.0.0.0:${port_snell_v4}
psk = ${snell_psk}
ipv6 = false
obfs = off
EOF
            nohup /opt/suoha_quick/snell-server -c /opt/suoha_quick/snell_v4.conf >/opt/suoha_quick/snell_v4.log 2>&1 &
            local snell_v4_pid=$!
            echo $snell_v4_pid > /opt/suoha_quick/snell_v4.pid
            sleep 0.5
            if kill -0 "$snell_v4_pid" 2>/dev/null; then
                snell_v4_ok=1
                snell_status="IPv4正常(端口:${port_snell_v4}) "
            fi
        fi

        if [ -n "$server_ipv6" ]; then
            cat > /opt/suoha_quick/snell_v6.conf <<EOF
[snell-server]
listen = [::]:${port_snell_v6}
psk = ${snell_psk}
ipv6 = true
obfs = off
EOF
            nohup /opt/suoha_quick/snell-server -c /opt/suoha_quick/snell_v6.conf >/opt/suoha_quick/snell_v6.log 2>&1 &
            local snell_v6_pid=$!
            echo $snell_v6_pid > /opt/suoha_quick/snell_v6.pid
            sleep 0.5
            if kill -0 "$snell_v6_pid" 2>/dev/null; then
                snell_v6_ok=1
                snell_status="${snell_status}IPv6正常(端口:${port_snell_v6})"
            else
                snell_status="${snell_status}IPv6监听失败:$(cat /opt/suoha_quick/snell_v6.log 2>/dev/null | tr '\n' ' ')"
            fi
        fi
    fi

    # 7. 获取机房归属标签并拉起双 Argo 隧道
    show_progress 70 "正在获取机房归属并建立 Argo 双协议隧道..."
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

    /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_vl}" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > /opt/suoha_quick/argo_vless.log 2>&1 &
    echo $! > /opt/suoha_quick/cf_vl.pid

    /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_tr}" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > /opt/suoha_quick/argo_trojan.log 2>&1 &
    echo $! > /opt/suoha_quick/cf_tr.pid

    local wait_sec=0
    local argo_vl=""
    local argo_tr=""
    while true; do
        wait_sec=$((wait_sec+1))
        argo_vl=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" /opt/suoha_quick/argo_vless.log 2>/dev/null | head -n 1 | awk -F// '{print $2}')
        argo_tr=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" /opt/suoha_quick/argo_trojan.log 2>/dev/null | head -n 1 | awk -F// '{print $2}')

        if [ -n "$argo_vl" ] && [ -n "$argo_tr" ]; then
            rm -f /opt/suoha_quick/argo_vless.log /opt/suoha_quick/argo_trojan.log
            show_progress 92 "Argo 双协议隧道域名分配成功！"
            break
        fi

        local dynamic_pct=$((74 + wait_sec))
        if [ $dynamic_pct -gt 91 ]; then
            dynamic_pct=91
        fi
        local status_vl="等待中"
        local status_tr="等待中"
        [ -n "$argo_vl" ] && status_vl="已就绪"
        [ -n "$argo_tr" ] && status_tr="已就绪"
        show_progress $dynamic_pct "等待 Argo 分配域名 (VLESS:${status_vl} | Trojan:${status_tr}) [${wait_sec}s]..."

        if [ $wait_sec -ge 25 ]; then
            wait_sec=0
            safe_kill_pidfile "/opt/suoha_quick/cf_vl.pid"
            safe_kill_pidfile "/opt/suoha_quick/cf_tr.pid"
            rm -f /opt/suoha_quick/argo_vless.log /opt/suoha_quick/argo_trojan.log
            show_progress 75 "Argo 获取超时，正在自动重连建立双隧道..."
            /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_vl}" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > /opt/suoha_quick/argo_vless.log 2>&1 &
            echo $! > /opt/suoha_quick/cf_vl.pid
            /opt/suoha_quick/cloudflared-linux tunnel --url "http://127.0.0.1:${port_argo_tr}" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > /opt/suoha_quick/argo_trojan.log 2>&1 &
            echo $! > /opt/suoha_quick/cf_tr.pid
            sleep 2
        else
            sleep 1
        fi
    done

    # 8. 生成全协议节点链接与 Clash / Mihomo 配置文件
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

    local direct_host=""
    local direct_yaml_host=""
    if [ -n "$server_ip" ]; then
        direct_host="$server_ip"
        direct_yaml_host="$server_ip"
    elif [ -n "$server_ipv6" ]; then
        direct_host="[${server_ipv6}]"
        direct_yaml_host="$server_ipv6"
    fi

    # (A) VLESS + REALITY 三件套组合 (严格匹配 Mihomo YAML 官方结构)
    local reality_summary=""
    if [ -n "$direct_host" ]; then
        local encoded_xhttp_path="%2Fxh-${short_id}"

        # 方案一（主力首选）：VLESS + TCP + REALITY + Vision
        local pname_rel_vision="${node_tag}-Reality-Vision-主力"
        local uri_rel_vision="vless://${uuid}@${direct_host}:${port_rel_vision}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${reality_pub}&sid=${reality_sid}&type=tcp&headerType=none#${pname_rel_vision}"
        echo "$uri_rel_vision" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_rel_vision")
        reality_summary+="[1. 主力首选 - TCP+Vision (端口:${port_rel_vision})]\n${uri_rel_vision}\n\n"
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_rel_vision}"
    type: vless
    server: ${direct_yaml_host}
    port: ${port_rel_vision}
    uuid: ${uuid}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${reality_sni}
    reality-opts:
      public-key: ${reality_pub}
      short-id: ${reality_sid}
      support-x25519mlkem768: false
    client-fingerprint: chrome
EOF

        # 方案二（现代备用）：VLESS + XHTTP + REALITY
        local pname_rel_xhttp="${node_tag}-Reality-XHTTP-备用"
        local uri_rel_xhttp="vless://${uuid}@${direct_host}:${port_rel_xhttp}?encryption=none&security=reality&sni=${reality_sni}&fp=chrome&pbk=${reality_pub}&sid=${reality_sid}&type=xhttp&path=${encoded_xhttp_path}&mode=auto#${pname_rel_xhttp}"
        echo "$uri_rel_xhttp" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_rel_xhttp")
        reality_summary+="[2. 现代备用 - XHTTP抗QoS (端口:${port_rel_xhttp})]\n${uri_rel_xhttp}\n\n"
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_rel_xhttp}"
    type: vless
    server: ${direct_yaml_host}
    port: ${port_rel_xhttp}
    uuid: ${uuid}
    network: xhttp
    tls: true
    udp: true
    servername: ${reality_sni}
    xhttp-opts:
      path: ${xhttp_path}
      mode: auto
    reality-opts:
      public-key: ${reality_pub}
      short-id: ${reality_sid}
      support-x25519mlkem768: false
    client-fingerprint: chrome
EOF

        # 方案三（老旧兼容/中转兜底）：VLESS + gRPC + REALITY
        local pname_rel_grpc="${node_tag}-Reality-gRPC-兼容"
        local uri_rel_grpc="vless://${uuid}@${direct_host}:${port_rel_grpc}?encryption=none&security=reality&sni=${reality_sni}&fp=chrome&pbk=${reality_pub}&sid=${reality_sid}&type=grpc&serviceName=${grpc_service}&mode=gun#${pname_rel_grpc}"
        echo "$uri_rel_grpc" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_rel_grpc")
        reality_summary+="[3. 兼容兜底 - gRPC中转 (端口:${port_rel_grpc})]\n${uri_rel_grpc}\n"
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_rel_grpc}"
    type: vless
    server: ${direct_yaml_host}
    port: ${port_rel_grpc}
    uuid: ${uuid}
    network: grpc
    tls: true
    udp: true
    servername: ${reality_sni}
    grpc-opts:
      grpc-service-name: ${grpc_service}
    reality-opts:
      public-key: ${reality_pub}
      short-id: ${reality_sid}
      support-x25519mlkem768: false
    client-fingerprint: chrome
EOF
    fi

    # (B) VLESS Argo 节点组
    local vless_domains=("$argo_vl" "${opt_domains[@]}")
    local vless_labels=("默认Argo" "${opt_labels[@]}")
    for idx in "${!vless_domains[@]}"; do
        local d="${vless_domains[$idx]}"
        local l="${vless_labels[$idx]}"
        local pname="${node_tag}-VLESS-${l}-443"
        echo "vless://${uuid}@${d}:443?encryption=none&security=tls&sni=${argo_vl}&type=ws&host=${argo_vl}&path=%2F${urlpath_vless}#${pname}" >> /opt/suoha_quick/nodes.txt
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
    servername: ${argo_vl}
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${argo_vl}
EOF
    done

    # (C) Trojan Argo 节点组
    local trojan_domains=("$argo_tr" "${opt_domains[@]}")
    local trojan_labels=("默认Argo" "${opt_labels[@]}")
    for idx in "${!trojan_domains[@]}"; do
        local d="${trojan_domains[$idx]}"
        local l="${trojan_labels[$idx]}"
        local pname="${node_tag}-Trojan-${l}-443"
        echo "trojan://${uuid}@${d}:443?security=tls&sni=${argo_tr}&type=ws&host=${argo_tr}&path=%2F${urlpath_trojan}#${pname}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname}"
    type: trojan
    server: ${d}
    port: 443
    password: ${uuid}
    udp: true
    sni: ${argo_tr}
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${argo_tr}
EOF
    done

    if [ -n "$direct_host" ]; then
        # (D) AnyTLS 直连节点
        local pname_any="${node_tag}-AnyTLS-Bing"
        echo "anytls://${password_all}@${direct_host}:${port_anytls}?sni=www.bing.com&insecure=1#${pname_any}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_any")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_any}"
    type: anytls
    server: ${direct_yaml_host}
    port: ${port_anytls}
    password: "${password_all}"
    client-fingerprint: chrome
    udp: true
    sni: www.bing.com
    skip-cert-verify: true
EOF

        # (E) Hysteria2 直连节点
        local pname_hy2="${node_tag}-Hysteria2-Bing"
        echo "hysteria2://${password_all}@${direct_host}:${port_hy2}?sni=www.bing.com&insecure=1#${pname_hy2}" >> /opt/suoha_quick/nodes.txt
        proxy_names+=("$pname_hy2")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_hy2}"
    type: hysteria2
    server: ${direct_yaml_host}
    port: ${port_hy2}
    password: "${password_all}"
    sni: www.bing.com
    skip-cert-verify: true
    alpn:
      - h3
EOF

        # (F) TUIC v5 直连节点
        local pname_tuic="${node_tag}-TUICv5-Bing"
        echo "tuic://${uuid}:${password_all}@${direct_host}:${port_tuic}?congestion_control=bbr&alpn=h3&sni=www.bing.com&udp_relay_mode=native&allow_insecure=1#${pname_tuic}" >> /opt/suoha_quick/nodes.txt
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
    sni: www.bing.com
    skip-cert-verify: true
EOF
    fi

    # (G) 原生 Shadowsocks IPv6 直连节点
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

    # (H) Snell 独立双栈节点
    local snell_display_lines=""
    if [ $snell_v4_ok -eq 1 ]; then
        local pname_snell_v4="${node_tag}-Snell-IPv4"
        proxy_names+=("$pname_snell_v4")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_snell_v4}"
    type: snell
    server: ${server_ip}
    port: ${port_snell_v4}
    psk: "${snell_psk}"
    version: 4
    udp: true
EOF
        local surge_v4="${pname_snell_v4} = snell, ${server_ip}, ${port_snell_v4}, psk=${snell_psk}, version=4, reuse=true"
        echo "$surge_v4" >> /opt/suoha_quick/surge.conf
        snell_display_lines+="${surge_v4}\n"
    fi

    if [ $snell_v6_ok -eq 1 ]; then
        local pname_snell_v6="${node_tag}-Snell-IPv6"
        proxy_names+=("$pname_snell_v6")
        cat >> /opt/suoha_quick/clash.yaml <<EOF
  - name: "${pname_snell_v6}"
    type: snell
    server: "${server_ipv6}"
    port: ${port_snell_v6}
    psk: "${snell_psk}"
    version: 4
    udp: true
EOF
        local surge_v6="${pname_snell_v6} = snell, ${server_ipv6}, ${port_snell_v6}, psk=${snell_psk}, version=4, reuse=true"
        echo "$surge_v6" >> /opt/suoha_quick/surge.conf
        snell_display_lines+="${surge_v6}\n"
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
        sub_host="$argo_vl"
    fi

    local sub_port
    sub_port=$(get_or_create_sub_port)
    sync_to_static_web "/opt/suoha_quick"
    start_sub_server "/var/www/suoha_sub" "$sub_port"

    local sub_online_url="http://${sub_host}:${sub_port}/sub.txt"
    local clash_online_url="http://${sub_host}:${sub_port}/clash.yaml"

    cat > /opt/suoha_quick/v2ray.txt <<EOF
======================== 服务器双栈网络与服务诊断 ========================
公网 IPv4: ${server_ip:-无} | 公网 IPv6 (出站实测): ${server_ipv6:-无可用 IPv6 出站}
Xray 状态: ${xray_status}
Snell 状态: ${snell_status:-未安装}

======================== VLESS + REALITY 三件套组合 ========================
共用参数 -> UUID: ${uuid} | SNI: ${reality_sni} | PublicKey: ${reality_pub} | ShortID: ${reality_sid}
已分配端口 -> Vision:${port_rel_vision} | XHTTP:${port_rel_xhttp} | gRPC:${port_rel_grpc}

$(echo -e "${reality_summary:-未检测到可用公网 IP，跳过 Reality 直连生成}")
======================== Shadowsocks IPv6 直连节点 ========================
${ss_v6_uri:-未检测到可用公网 IPv6 出站，跳过 SS-IPv6 生成}

======================== 全协议节点汇总 (含 Argo / AnyTLS / HY2 / TUIC / SS-IPv6) ========================
$(cat /opt/suoha_quick/nodes.txt)

[Snell 双栈独立配置]
$(echo -e "${snell_display_lines:-未检测到可用公网 IP，跳过 Snell 生成}")
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

    show_progress 100 "全部协议及 Reality 三件套 + SS-IPv6 部署完成！"
    sleep 0.6
    clear
    cat /opt/suoha_quick/v2ray.txt
    echo -e "\n所有配置已保存至 /opt/suoha_quick/v2ray.txt，随时执行 cat /opt/suoha_quick/v2ray.txt 查看。"
}

quicktunnel_all_in_one
