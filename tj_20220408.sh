############################################################################
############################################################################
########################### Updated: 2024-11-26 ###########################
############################################################################
############################################################################

#!/bin/bash

function green(){
	echo -e "\033[32m\033[01m$1\033[0m"
}
function yellow(){
	echo -e "\033[33m\033[01m$1\033[0m"
}
function purple(){
	echo -e "\033[45m\033[01m$1\033[0m"
}


function installCert(){
	yellow ">>>>>>>> 安装证书"
	~/.acme.sh/acme.sh  --installcert  -d  $1   \
        --key-file   /etc/nginx/ssl/$1.key \
        --fullchain-file /etc/nginx/ssl/$1.crt \
        --reloadcmd  "/etc/init.d/nginx restart" \
        --ecc
}

function installNginx(){
	echo
	echo
	green "===============安装nginx==============="
	apt-get install -y nginx || return 100
	yellow ">>>> nginx安装成功"


	green "===============修改nginx目录为当前用户==============="
	chown -R $(whoami) /etc/nginx/ || return 101
	ls -l /etc/nginx/
	chown -R $(whoami) /usr/share/nginx/ || return 102
	ls -l /usr/share/nginx/

	echo
	echo
	green "===============配置nginx==============="
	yellow ">>>>>>>> 删除默认配置"
	rm /etc/nginx/sites-enabled/*
	echo "echo ls -l /etc/nginx/sites-enabled/"
	ls -l /etc/nginx/sites-enabled/

	yellow ">>>>>>>> 生成配置文件"
	cat > /etc/nginx/nginx.conf <<-EOF
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
	echo "echo /etc/nginx/nginx.conf"
	cat /etc/nginx/nginx.conf

	cat > /etc/nginx/sites-available/$1.conf<<-EOF
	server {
	    listen 127.0.0.1:80 default_server;

	    server_name $1;

	    location / {
	        root /usr/share/nginx/html;
	        index index.php index.html index.htm;
	    }
	}

	server {
	    listen 127.0.0.1:80;

	    server_name $2;
	    return 301 https://$1\$request_uri;
	}

	server {
	    listen 0.0.0.0:80;
	    listen [::]:80;

	    server_name $1;
	    location /.well-known {
	        root /usr/share/nginx/html;
	        index index.php index.html index.htm;
	    }
	    location / {
	        return 301 https://\$host\$request_uri;
	    }
	}

	server {
	    listen 0.0.0.0:80;
	    listen [::]:80;

	    server_name _;
	    return 301 https://\$host\$request_uri;
	}
	EOF
	echo
	echo "echo /etc/nginx/sites-available/$1.conf"
	cat /etc/nginx/sites-available/$1.conf

	yellow ">>>>>>>> 配置nginx服务"
	ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/
	echo "ls -l /etc/nginx/sites-enabled/"
	ls -l /etc/nginx/sites-enabled/


	yellow ">>>>>>>> 配置马甲站点"
	rm -rf /usr/share/nginx/html
	cd /usr/share/nginx/
	wget https://raw.githubusercontent.com/skycar8/free/master/car.zip
	unzip car.zip
	rm car.zip
	yellow "ls -l /usr/share/nginx/html"
	ls -l /usr/share/nginx/html

	yellow "===启动nginx==="
	systemctl restart nginx  || return 103
	systemctl status nginx
	yellow "===nginx启动成功==="

	yellow ">>>>>>>> 设置nginx开机启动"
	systemctl enable nginx.service
}


function installTrojan(){
	echo
	echo
	green "===============安装trojan==============="
	# 安装trojan
	echo y | bash -c "$(curl -fsSL https://raw.githubusercontent.com/trojan-gfw/trojan-quickstart/master/trojan-quickstart.sh)" || return 200

	green "===============修改trojan目录为当前用户==============="
	chown -R $(whoami) /usr/local/etc/trojan/ || return 201
	ls -l /usr/local/etc/trojan/

	yellow ">>>>>>>> 生成随机密码"
	password=$(cat /dev/urandom | head -1 | md5sum | head -c 32)
	purple "随机密码: $password"

	yellow ">>>>>>>> 生成trojan配置文件"
	cat > /usr/local/etc/trojan/config.json <<-EOF
	{
	    "run_type": "server",
	    "local_addr": "0.0.0.0",
	    "local_port": 443,
	    "remote_addr": "127.0.0.1",
	    "remote_port": 80,
	    "password": [
	        "$password"
	    ],
	    "log_level": 1,
	    "ssl": {
	        "cert": "/etc/nginx/ssl/$1.crt",
	        "key": "/etc/nginx/ssl/$1.key",
	        "key_password": "",
	        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
	        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
	        "prefer_server_cipher": true,
	        "alpn": [
	            "http/1.1"
	        ],
	        "alpn_port_override": {
	            "h2": 81
	        },
	        "reuse_session": true,
	        "session_ticket": false,
	        "session_timeout": 600,
	        "plain_http_response": "",
	        "curves": "",
	        "dhparam": ""
	    },
	    "tcp": {
	        "prefer_ipv4": false,
	        "no_delay": true,
	        "keep_alive": true,
	        "reuse_port": false,
	        "fast_open": false,
	        "fast_open_qlen": 20
	    },
	    "mysql": {
	        "enabled": false,
	        "server_addr": "127.0.0.1",
	        "server_port": 3306,
	        "database": "trojan",
	        "username": "trojan",
	        "password": "",
	        "cafile": ""
	    }
	}
	EOF
	echo "/usr/local/etc/trojan/config.json"
	cat /usr/local/etc/trojan/config.json

	yellow "===启动trojan==="
	systemctl restart trojan  || return 202
	systemctl status trojan
	yellow "===trojan启动成功==="

    	yellow ">>>>>>>> 设置trojan自动更新证书"
    	sh -c 'echo "0 0 1 * * killall -s SIGUSR1 trojan" >> /var/spool/cron/crontabs/root'
    	cat /var/spool/cron/crontabs/root

	yellow ">>>>>>>> 设置torjan开机启动"
	systemctl enable trojan.service
}





green "===============安装常用软件包==============="
apt-get -y update
apt-get -y install unzip zip wget curl vim socat ntp ntpdate gcc git xz-utils || exit 100





echo
echo
green "=========================================="
green "输入解析到此VPS的域名"
green "=========================================="
read domain
# 校验域名





echo
echo
green "===============获取本机ip地址==============="
# 获取本机ip地址
# curl icanhazip.com
# curl ident.me
# curl ipecho.net/plain
# curl whatismyip.akamai.com
# curl tnx.nl/ip
# curl myip.dnsomatic.com
# curl ip.appspot.com
ipAddr=$(curl ifconfig.me)
purple ">>>>>>>> 本机ip: $ipAddr"





# 安装nginx
installNginx $domain $ipAddr || exit 100





echo
echo
green "===============安装SSL证书==============="

yellow ">>>>>>>> 创建证书文件夹"
mkdir /etc/nginx/ssl
yellow "ls -l /etc/nginx/ssl"
ls -l /etc/nginx/ssl

yellow ">>>>>>>> 安装acme"
curl https://get.acme.sh | sh  || exit 300
# 自动更新acme
~/.acme.sh/acme.sh  --upgrade  --auto-upgrade

yellow ">>>>>>>> 设置ZeroSSL账号"
~/.acme.sh/acme.sh  --register-account  --server zerossl \
        --eab-kid  SW743Pz5NW4Fo_R_JKSRbQ  \
        --eab-hmac-key  uavWo9Ae_TlX05_ls5klOUKiU0HAFBKNPdZ-HL2ZU-5YCR5SOuWbT6lX-kU3ILOxJXEYgfKDzUVaNbfJMsvF9w

yellow ">>>>>>>> 申请证书"
~/.acme.sh/acme.sh  --issue  -d $domain  \
	--webroot /usr/share/nginx/html/  \
	-k ec-256  \
	--force  --debug || exit 301
installCert $domain || exit 302





# 安装trojan
installTrojan $domain || exit 200





echo
echo
green "===============trojan安装OK==============="
green "trojan连接密码："
green "$password"
green "========================================="





echo
echo
green "===============开启bbr加速==============="
# 开启bbr加速
sh -c 'echo net.core.default_qdisc=fq >> /etc/sysctl.conf'
sh -c 'echo net.ipv4.tcp_congestion_control=bbr >> /etc/sysctl.conf'
sysctl -p

yellow ">>>>>>>> sysctl net.ipv4.tcp_available_congestion_control"
sysctl net.ipv4.tcp_available_congestion_control
#rootMF8-BIZ sysctl net.ipv4.tcp_available_congestion_control
#net.ipv4.tcp_available_congestion_control = bbr cubic reno

yellow ">>>>>>>> lsmod | grep bbr"
lsmod | grep bbr
#tcp_bbr                20480  11
