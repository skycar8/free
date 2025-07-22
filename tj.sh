#!/bin/bash

function green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
function yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
function purple(){ echo -e "\033[45m\033[01m$1\033[0m"; }

function installCert(){
    yellow ">>>>>> Installing SSL certificate for $1"
    ~/.acme.sh/acme.sh --install-cert -d $1 \
        --key-file /etc/nginx/ssl/$1.key \
        --fullchain-file /etc/nginx/ssl/$1.crt \
        --reloadcmd "systemctl reload nginx" \
        --ecc
}

function setupFirewall(){
    green "Configuring firewall..."
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
}

function disableSELinux(){
    yellow "Disabling SELinux..."
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
}

function installNginx(){
    green "Installing nginx..."
    dnf install -y epel-release nginx || exit 100
    systemctl enable nginx
    mkdir -p /etc/nginx/ssl
    cat > /etc/nginx/nginx.conf <<EOF
user root;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 50m;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    cat > /etc/nginx/conf.d/$1.conf <<EOF
server {
    listen 80;
    server_name $1;
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }
}
EOF
    systemctl restart nginx || exit 101
}

function installTrojan(){
    green "Installing trojan..."
    dnf install -y curl jq || exit 200
    bash <(curl -fsSL https://raw.githubusercontent.com/trojan-gfw/trojan-quickstart/master/trojan-quickstart.sh)
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    purple "Generated Trojan password: $PASSWORD"
    cat > /usr/local/etc/trojan/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$PASSWORD"],
  "ssl": {
    "cert": "/etc/nginx/ssl/$1.crt",
    "key": "/etc/nginx/ssl/$1.key",
    "alpn": ["http/1.1"],
    "session_timeout": 600
  },
  "tcp": {
    "prefer_ipv4": true
  }
}
EOF
    systemctl restart trojan || exit 202
    systemctl enable trojan
    echo "0 0 * * * systemctl reload trojan" | crontab -
}

# Main script execution
green "Updating system and installing essentials..."
dnf -y update
dnf -y install unzip zip wget curl vim socat ntp gcc git xz firewalld

disableSELinux
setupFirewall

green "Please enter your domain name: "
read DOMAIN

IP=$(curl ipinfo.io/ip)
purple "Detected IP: $IP"

installNginx $DOMAIN

curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m your-email@example.com --server zerossl
~/.acme.sh/acme.sh --issue -d $DOMAIN --webroot /usr/share/nginx/html --keylength ec-256
installCert $DOMAIN

installTrojan $DOMAIN

sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -p

purple "Trojan installation complete! Password: $PASSWORD"
