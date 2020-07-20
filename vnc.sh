#!/bin/bash

# 在您的服务器上，更新您的包列表：
grep y | sudo apt update

# 现在在您的服务器上安装Xfce桌面环境：
grep y | sudo apt install xfce4 xfce4-goodies

# 安装完成后，安装TightVNC服务器：
grep y | sudo apt install tightvncserver

vncserver
vncserver -kill :1
mv ~/.vnc/xstartup ~/.vnc/xstartup.bak
touch ~/.vnc/xstartup

echo '#!/bin/bash' >> ~/.vnc/xstartup
echo 'xrdb $HOME/.Xresources' >> ~/.vnc/xstartup
echo 'startxfce4 &' >> ~/.vnc/xstartup

sudo chmod +x ~/.vnc/xstartup
vncserver
