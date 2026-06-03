#!/bin/bash

# ====================================================
# Xray-core VLESS 自动部署脚本 (REALITY / XHTTP-TLS)
# 支持系统: Ubuntu 20.04+, Debian 11+, CentOS 8+
# ====================================================

# 字体颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 检测系统架构与发行版
if [[ -f /etc/redhat-release ]]; then
    OS="CentOS"
elif cat /etc/issue | grep -Eqi "debian"; then
    OS="Debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    OS="Ubuntu"
elif cat /etc/etc-release | grep -Eqi "centos|redhat"; then
    OS="CentOS"
elif cat /proc/version | grep -Eqi "debian"; then
    OS="Debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    OS="Ubuntu"
else
    echo -e "${RED}未检测到受支持的系统，请使用 Ubuntu/Debian/CentOS ${PLAIN}" && exit 1
fi

echo -e "${GREEN}系统检测完毕，当前系统为: ${OS}${PLAIN}"

# 安装基础依赖
install_dependencies() {
    echo -e "${BLUE}正在安装基础依赖组件...${PLAIN}"
    if [[ "${OS}" == "CentOS" ]]; then
        yum install -y curl wget jq uuidgen socat epel-release
    else
        apt update -y
        apt install -y curl wget jq uuid-runtime socat
    fi
}

# 安装/更新 Xray-core 官方最新版
install_xray() {
    echo -e "${BLUE}正在通过官方脚本安装最新版 Xray-core...${PLAIN}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Xray-core 安装失败，请检查网络！${PLAIN}"
        exit 1
    fi
    systemctl enable xray
}

# 模式 1: 配置 VLESS-REALITY
config_reality() {
    UUID=$(uuidgen)
    # 获取 Xray 生成的 X25519 密钥
    X25519_KEY=$(xray x25519)
    PRIVATE_KEY=$(echo "$X25519_KEY" | grep "Private key" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$X25519_KEY" | grep "Public key" | awk '{print $3}')
    SHORT_ID=$(head /dev/urandom | tr -dc 'a-f0-9' | head -c 12)
    
    echo -e "${YELLOW}请输入需要借用的目标域名 (默认: images.apple.com):${PLAIN}"
    read -p "Target Domain: " DEST_DOMAIN
    [[ -z "$DEST_DOMAIN" ]] && DEST_DOMAIN="images.apple.com"

    cat <<EOF > /usr/local/etc/xray/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {"id": "${UUID}", "flow": "xtls-rprx-vision"}
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${DEST_DOMAIN}:443",
                    "xver": 0,
                    "serverNames": ["${DEST_DOMAIN}"],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": ["${SHORT_ID}"]
                }
            }
        }
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"}
    ]
}
EOF

    restart_and_show_info "REALITY" "$UUID" "443" "$DEST_DOMAIN" "$PUBLIC_KEY" "$SHORT_ID"
}

# 模式 2: 配置 VLESS-XHTTP-TLS (套 Cloudflare 救砖)
config_xhttp_tls() {
    UUID=$(uuidgen)
    
    echo -e "${YELLOW}请输入你在 Cloudflare 托管并解析到此服务器的【完整域名】:${PLAIN}"
    read -p "Your Domain: " MY_DOMAIN
    while [[ -z "$MY_DOMAIN" ]]; do
        echo -e "${RED}域名不能为空，请输入有效域名：${PLAIN}"
        read -p "Your Domain: " MY_DOMAIN
    done

    echo -e "${YELLOW}请输入自定义伪装路径 (默认: /download):${PLAIN}"
    read -p "Path: " WSPATH
    [[ -z "$WSPATH" ]] && WSPATH="/download"

    echo -e "${BLUE}提示：正在准备本地证书环境...${PLAIN}"
    echo -e "${YELLOW}请粘贴你在 Cloudflare [源服务器] 生成的 [源证书 (Origin Certificate)] 内容，输完后按 Ctrl+D 保存：${PLAIN}"
    cat > /usr/local/etc/xray/server.crt
    
    echo -e "${YELLOW}请粘贴你在 Cloudflare [源服务器] 生成的 [私钥 (Private Key)] 内容，输完后按 Ctrl+D 保存：${PLAIN}"
    cat > /usr/local/etc/xray/server.key

    cat <<EOF > /usr/local/etc/xray/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {"id": "${UUID}"}
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "${MY_DOMAIN}",
                    "certificates": [
                        {
                            "certificateFile": "/usr/local/etc/xray/server.crt",
                            "keyFile": "/usr/local/etc/xray/server.key"
                        }
                    ]
                },
                "xhttpSettings": {
                    "path": "${WSPATH}"
                }
            }
        }
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"}
    ]
}
EOF

    restart_and_show_info "XHTTP-TLS" "$UUID" "443" "$MY_DOMAIN" "" "" "$WSPATH"
}

# 重启并输出配置结果
restart_and_show_info() {
    TYPE=$1
    UUID=$2
    PORT=$3
    DOMAIN=$4
    PUB_KEY=$5
    S_ID=$6
    XPATH=$7

    echo -e "${BLUE}正在重启 Xray 服务...${PLAIN}"
    systemctl restart xray
    sleep 1

    if systemctl is-active xray &>/dev/null; then
        echo -e "\n${GREEN}==================================================${PLAIN}"
        echo -e "${GREEN} 💥 Xray ${TYPE} 模式部署成功！${PLAIN}"
        echo -e "${GREEN}==================================================${PLAIN}"
        echo -e "${BLUE}协议类型 (Protocol):${PLAIN} VLESS"
        echo -e "${BLUE}端口 (Port):${PLAIN} ${PORT}"
        echo -e "${BLUE}用户 ID (UUID):${PLAIN} ${UUID}"
        
        if [[ "$TYPE" == "REALITY" ]]; then
            echo -e "${BLUE}流控 (Flow):${PLAIN} xtls-rprx-vision"
            echo -e "${BLUE}传输网络 (Network):${PLAIN} tcp"
            echo -e "${BLUE}安全传输 (Security):${PLAIN} reality"
            echo -e "${BLUE}SNI / Target Peer:${PLAIN} ${DOMAIN}"
            echo -e "${BLUE}公钥 (PublicKey):${PLAIN} ${PUB_KEY}"
            echo -e "${BLUE}简短 ID (ShortId):${PLAIN} ${S_ID}"
            echo -e "${YELLOW}提示：REALITY 属于直连高抗封锁模式，不能在 Cloudflare 中点亮小云朵。${PLAIN}"
        else
            echo -e "${BLUE}传输网络 (Network):${PLAIN} xhttp"
            echo -e "${BLUE}安全传输 (Security):${PLAIN} tls"
            echo -e "${BLUE}伪装域名 / SNI:${PLAIN} ${DOMAIN}"
            echo -e "${BLUE}路径 (Path):${PLAIN} ${XPATH}"
            echo -e "${YELLOW}提示：请务必在 Cloudflare 开启 Proxy 状态（点亮橙色小云朵）来拯救被墙的 IP。${PLAIN}"
        fi
        echo -e "${GREEN}==================================================${PLAIN}\n"
    else
        echo -e "${RED}错误：Xray 启动失败！请运行 'systemctl status xray' 或 'journalctl -u xray' 查看错误日志。${PLAIN}"
    fi
}

# 脚本主菜单
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "${GREEN}    Xray-core 一键三系统全自动部署脚本 2026          ${PLAIN}"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e " 1. 部署 VLESS-REALITY 模式 (新服务器直连极速推荐)"
echo -e " 2. 部署 VLESS-XHTTP-TLS 模式 (IP已墙，套 Cloudflare 救砖)"
echo -e " 3. 卸载 Xray 服务"
echo -e " 0. 退出脚本"
echo -e "${GREEN}==================================================${PLAIN}"
read -p "请选择操作 [0-3]: " CHOICE

case "$CHOICE" in
    1)
        install_dependencies
        install_xray
        config_reality
        ;;
    2)
        install_dependencies
        install_xray
        config_xhttp_tls
        ;;
    3)
        echo -e "${YELLOW}正在完全卸载 Xray...${PLAIN}"
        systemctl stop xray
        systemctl disable xray
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove
        rm -rf /usr/local/etc/xray
        echo -e "${GREEN}Xray 卸载完成。${PLAIN}"
        ;;
    *)
        echo -e "${BLUE}已退出脚本。${PLAIN}"
        exit 0
        ;;
esac
