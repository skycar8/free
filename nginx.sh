#!/bin/bash

function blue(){ echo -e "\033[34m\033[01m $1 \033[0m" }
function green(){ echo -e "\033[32m\033[01m $1 \033[0m" }
function red(){ echo -e "\033[31m\033[01m $1 \033[0m" }
function yellow(){ echo -e "\033[33m\033[01m $1 \033[0m" }

# 安装常用软件包
sudo apt-get -y update && apt-get -y install unzip zip wget curl nano sudo ufw socat ntp ntpdate gcc git xz-utils

# 读取域名
green "======================"
green " 输入解析到此VPS的域名"
green "======================"
read domain
# 校验域名

# 获取本机ip地址
# curl icanhazip.com
# curl ident.me
# curl ipecho.net/plain
# curl whatismyip.akamai.com
# curl tnx.nl/ip
# curl myip.dnsomatic.com
# curl ip.appspot.com
ipAddr=$(curl ifconfig.me)

# 读取Cloudflare Email和Key
# read CF_Email
# 校验email
# read CF_Key
# 添加Cloudflare域名解析



green "===============安装nginx==============="
# 安装nginx
sudo yum install -y nginx

# 删除默认配置
sudo rm /etc/nginx/sites-enabled/default
# 生成配置文件
sudo cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}
EOF

cat > /etc/nginx/sites-available/$domain.conf<<-EOF
server {
    listen 127.0.0.1:80 default_server;
    server_name $domain;
    location / {
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
    # error_page   500 502 503 504  /50x.html;
    # location = /50x.html {
    #     root   /usr/share/nginx/html;
    # }
}
server {
    listen 127.0.0.1:80;
    server_name $ipAddr;
    return 301 https://$domain$request_uri;
}
server {
    listen 0.0.0.0:80;
    listen [::]:80;
    server_name _;
   	return 301 https://$host$request_uri;
}
EOF

# 配置nginx服务
sudo ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/

# 配置马甲站点
rm -rf /usr/share/nginx/html
cd /usr/share/nginx/
wget https://raw.githubusercontent.com/skycar8/free/master/car.zip
unzip car.zip
rm car.zip

# 启动nginx
sudo systemctl restart nginx
sudo systemctl status nginx

# nginx开机启动
sudo systemctl enable nginx.service
