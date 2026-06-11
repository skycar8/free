#!/bin/bash

# ====================================================
# Xray-core Ultimate Script (Shadowrocket & ClashX)
# Features: REALITY, XHTTP-TLS, QR Codes, Subscriptions, Uninstaller
# Supports: Ubuntu 20.04+, Debian 11+, CentOS 8+
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Error: Must be run as root!${PLAIN}" && exit 1

# Detect OS
if [[ -f /etc/redhat-release ]] || cat /etc/os-release | grep -Eqi "centos|redhat"; then
    OS="CentOS"
elif cat /etc/os-release | grep -Eqi "debian"; then
    OS="Debian"
elif cat /etc/os-release | grep -Eqi "ubuntu"; then
    OS="Ubuntu"
else
    echo -e "${RED}Unsupported OS!${PLAIN}" && exit 1
fi

SUB_DIR="/usr/local/etc/xray/sub"
ROCKET_FILE="${SUB_DIR}/rocket.txt"
CLASH_FILE="${SUB_DIR}/clash.yaml"

install_dependencies() {
    echo -e "${BLUE}Installing dependencies...${PLAIN}"
    if [[ "${OS}" == "CentOS" ]]; then
        yum install -y curl wget jq uuidgen socat python3 epel-release
        yum install -y qrencode || echo "QR tool skipped"
    else
        apt update -y
        apt install -y curl wget jq uuid-runtime socat python3 qrencode
    fi
    mkdir -p "$SUB_DIR"
}

install_xray() {
    echo -e "${BLUE}Installing/Updating Xray-core...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    systemctl enable xray
}

generate_subscriptions() {
    CONF_FILE="/usr/local/etc/xray/config.json"
    if [[ ! -f "$CONF_FILE" ]]; then
        echo -e "${RED}Xray configuration file not found!${PLAIN}"
        return 1
    fi

    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONF_FILE")
    PORT=$(jq -r '.inbounds[0].port' "$CONF_FILE")
    SECURITY=$(jq -r '.inbounds[0].streamSettings.security' "$CONF_FILE")
    IP=$(curl -s https://api.ipify.org)

    if [[ "$SECURITY" == "reality" ]]; then
        SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONF_FILE")
        SH_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONF_FILE")
        [[ -f "/usr/local/etc/xray/pub.key" ]] && PUB_KEY=$(cat /usr/local/etc/xray/pub.key) || PUB_KEY=""

        # 1. Shadowrocket Link
        ROCKET_LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB_KEY}&sid=${SH_ID}#REALITY_Direct"
        
        # 2. Clash Meta Proxy Block
        CLASH_PROXY="  - name: \"REALITY_Direct\"\n    type: vless\n    server: ${IP}\n    port: ${PORT}\n    uuid: ${UUID}\n    cipher: none\n    flow: xtls-rprx-vision\n    tls: true\n    reality-opts:\n      public-key: ${PUB_KEY}\n      short-id: ${SH_ID}\n    client-fingerprint: chrome\n    servername: ${SNI}"
    else
        SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName' "$CONF_FILE")
        XPATH=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "$CONF_FILE")
        XPATH_CLEAN=${XPATH///}

        # 1. Shadowrocket Link
        ROCKET_LINK="vless://${UUID}@${SNI}:${PORT}?encryption=none&security=tls&sni=${SNI}&type=xhttp&path=%2F${XPATH_CLEAN}#Cloudflare_CDN"
        
        # 2. Clash Meta Proxy Block
        CLASH_PROXY="  - name: \"Cloudflare_CDN\"\n    type: vless\n    server: ${SNI}\n    port: ${PORT}\n    uuid: ${UUID}\n    cipher: none\n    tls: true\n    servername: ${SNI}\n    network: xhttp\n    xhttp-opts:\n      path: /${XPATH_CLEAN}"
    fi

    # Write Shadowrocket File
    echo "$ROCKET_LINK" | base64 | tr -d '\n' > "$ROCKET_FILE"

    # Write Complete Clash Configuration File
    cat <<EOF > "$CLASH_FILE"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'

proxies:
$(echo -e "$CLASH_PROXY")

proxy-groups:
  - name: 🚀 Proxy
    type: select
    proxies:
      - REALITY_Direct
      - Cloudflare_CDN
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,🚀 Proxy
EOF

    echo -e "${GREEN}Both subscription profiles successfully updated!${PLAIN}"
}

config_reality() {
    UUID=$(uuidgen)
    X25519_KEY=$(xray x25519)
    PRIVATE_KEY=$(echo "$X25519_KEY" | awk -F': ' '/PrivateKey/ {print $2}')
    PUBLIC_KEY=$(echo "$X25519_KEY" | awk -F': ' '/PublicKey/ {print $2}')
    echo "$PUBLIC_KEY" > /usr/local/etc/xray/pub.key
    SHORT_ID=$(head /dev/urandom | tr -dc 'a-f0-9' | head -c 12)
    
    read -p "Target Domain (Default: images.apple.com): " DEST_DOMAIN
    [[ -z "$DEST_DOMAIN" ]] && DEST_DOMAIN="images.apple.com"

    cat <<EOF > /usr/local/etc/xray/config.json
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "port": 443, "protocol": "vless",
        "settings": {"clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none"},
        "streamSettings": {
            "network": "tcp", "security": "reality",
            "realitySettings": {
                "show": false, "dest": "${DEST_DOMAIN}:443", "xver": 0,
                "serverNames": ["${DEST_DOMAIN}"], "privateKey": "${PRIVATE_KEY}", "shortIds": ["${SHORT_ID}"]
            }
        }
    }],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    restart_and_show_info "REALITY" "$UUID" "443" "$DEST_DOMAIN" "$PUBLIC_KEY" "$SHORT_ID"
    generate_subscriptions
    serve_subscriptions
}

config_xhttp_tls() {
    UUID=$(uuidgen)
    read -p "Enter your Cloudflare Domain: " MY_DOMAIN
    while [[ -z "$MY_DOMAIN" ]]; do read -p "Domain cannot be empty: " MY_DOMAIN; done
    read -p "Custom Path (Default: /download): " WSPATH
    [[ -z "$WSPATH" ]] && WSPATH="/download"

    echo -e "${YELLOW}Paste Cloudflare Certificate, then press Ctrl+D:${PLAIN}"
    cat > /usr/local/etc/xray/server.crt
    echo -e "${YELLOW}Paste Cloudflare Private Key, then press Ctrl+D:${PLAIN}"
    cat > /usr/local/etc/xray/server.key

    cat <<EOF > /usr/local/etc/xray/config.json
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "port": 443, "protocol": "vless",
        "settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
        "streamSettings": {
            "network": "xhttp", "security": "tls",
            "tlsSettings": {"serverName": "${MY_DOMAIN}", "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]},
            "xhttpSettings": {"path": "${WSPATH}"}
        }
    }],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    restart_and_show_info "XHTTP-TLS" "$UUID" "443" "$MY_DOMAIN" "" "" "$WSPATH"
    generate_subscriptions
    serve_subscriptions
}

serve_subscriptions() {
    if [[ ! -f "$ROCKET_FILE" ]] || [[ ! -f "$CLASH_FILE" ]]; then
        echo -e "${RED}Subscription files missing! Please configure a node first.${PLAIN}"
        return
    fi

    IP=$(curl -s https://api.ipify.org)
    PORT=8080
    ROCKET_URL="http://${MY_DOMAIN:-$IP}:${PORT}/rocket.txt"
    CLASH_URL="http://${MY_DOMAIN:-$IP}:${PORT}/clash.yaml"

    echo -e "\n${GREEN}==================================================${PLAIN}"
    echo -e "${YELLOW}  🚀 Dual Subscription Engine Active!             ${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
    echo -e "${BLUE}📱 Shadowrocket Sub Link:${PLAIN} ${ROCKET_URL}"
    echo -e "${BLUE}🐱 ClashX / Meta Sub Link:${PLAIN} ${CLASH_URL}"
    echo -e "${GREEN}==================================================${PLAIN}"
    
    if command -v qrencode &>/dev/null; then
        echo -e "\n${BLUE}👉 [1/2] Scan for Shadowrocket Subscription:${PLAIN}"
        qrencode -t ansiutf8 "$ROCKET_URL"
        
        echo -e "\n${BLUE}👉 [2/2] Scan for ClashX / Meta Subscription:${PLAIN}"
        qrencode -t ansiutf8 "$CLASH_URL"
    else
        echo -e "${YELLOW}qrencode not installed. Displaying URLs only.${PLAIN}"
    fi
    
    echo -e "\n${RED}Press Ctrl+C to close the temporary server once you are synced.${PLAIN}\n"
    
    cd "$SUB_DIR" || exit
    python3 -m http.server $PORT
}

uninstall_all() {
    echo -e "${YELLOW}Are you sure you want to completely uninstall Xray and remove all configuration/subscription data? [y/N]${PLAIN}"
    read -p "Uninstall? " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Stopping and disabling Xray service...${PLAIN}"
        systemctl stop xray &>/dev/null
        systemctl disable xray &>/dev/null
        
        echo -e "${BLUE}Running official removal script...${PLAIN}"
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove &>/dev/null
        
        echo -e "${BLUE}Cleaning remaining files and configuration directories...${PLAIN}"
        rm -rf /usr/local/etc/xray
        rm -rf /usr/local/share/xray
        rm -rf /var/log/xray
        
        echo -e "${GREEN}Everything related to Xray-core has been completely wiped from this system.${PLAIN}"
    else
        echo -e "${BLUE}Uninstall canceled.${PLAIN}"
    fi
}

restart_and_show_info() {
    TYPE=$1
    UUID=$2
    PORT=$3
    DOMAIN=$4
    PUB_KEY=$5
    S_ID=$6
    XPATH=$7

    echo -e "${BLUE}Restarting Xray service...${PLAIN}"
    systemctl restart xray
    sleep 2

    if systemctl is-active xray &>/dev/null; then
        echo -e "\n${GREEN}==================================================${PLAIN}"
        echo -e "${GREEN} 💥 Xray ${TYPE} Deployed！${PLAIN}"
        echo -e "${GREEN}==================================================${PLAIN}"
        echo -e "${BLUE}Protocol:${PLAIN} VLESS"
        echo -e "${BLUE}Port:${PLAIN} ${PORT}"
        echo -e "${BLUE}UUID:${PLAIN} ${UUID}"

        if [[ "$TYPE" == "REALITY" ]]; then
            echo -e "${BLUE}Flow:${PLAIN} xtls-rprx-vision"
            echo -e "${BLUE}Network:${PLAIN} tcp"
            echo -e "${BLUE}Security:${PLAIN} reality"
            echo -e "${BLUE}SNI / Target Peer:${PLAIN} ${DOMAIN}"
            echo -e "${BLUE}PublicKey:${PLAIN} ${PUB_KEY}"
            echo -e "${BLUE}ShortId:${PLAIN} ${S_ID}"
            echo -e "${YELLOW}Hint: REALITY is a direct-connection, high-censorship-resistance mode; you cannot enable the Cloudflare proxy (the orange cloud icon ☁️) for it.${PLAIN}"
        else
            echo -e "${BLUE}Network:${PLAIN} xhttp"
            echo -e "${BLUE}Security:${PLAIN} tls"
            echo -e "${BLUE}Fake Domain / SNI:${PLAIN} ${DOMAIN}"
            echo -e "${BLUE}Path:${PLAIN} ${XPATH}"
            echo -e "${YELLOW}Hint: Please make sure to enable Cloudflare's Proxy status (turn on the orange cloud ☁️) to rescue the blocked/GFWed IP.${PLAIN}"
        fi
        echo -e "${GREEN}==================================================${PLAIN}\n"
    else
        echo -e "${RED}ERROR：Xray Start failed！Please run 'systemctl status xray' OR 'journalctl -u xray' to check the log.${PLAIN}"
    fi
}

# Main Menu
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "${GREEN}    Xray Multi-Client Tool & Subscription Center   ${PLAIN}"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e " 1. Setup VLESS-REALITY Node + Update Profiles"
echo -e " 2. Setup VLESS-XHTTP-TLS Node + Update Profiles"
echo -e " 3. Host Subscriptions & Generate QR Codes"
echo -e " 4. Uninstall Xray-core & Wipe All Data"
echo -e " 0. Exit"
echo -e "${GREEN}==================================================${PLAIN}"
read -p "Select [0-4]: " CHOICE

case "$CHOICE" in
    1) install_dependencies; install_xray; config_reality ;;
    2) install_dependencies; install_xray; config_xhttp_tls ;;
    3) serve_subscriptions ;;
    4) uninstall_all ;;
    *) exit 0 ;;
esac
