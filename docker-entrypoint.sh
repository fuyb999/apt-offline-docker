#!/bin/bash

RESTORE='\033[0m'
RED='\033[00;31m'

SAVE_PATH=/tmp/debs
sed -i -E "s/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" /etc/apt/sources.list

REQUIRE_PKG="curl wget gpg lsb_release add-apt-repository"
apt-get update && apt-get install -y curl wget gpg lsb-core software-properties-common python3

if [ -n "$(echo $PKG_DOWNLOAD_LIST | grep 'nvidia-container-toolkit')" ]; then
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
   && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
   sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
   tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
fi

if [ -n "$(echo $PKG_DOWNLOAD_LIST | grep 'docker-ce')" ]; then
  curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
fi

if [ -n "$(echo $PKG_DOWNLOAD_LIST | grep 'google-chrome-stable')" ]; then
  curl -fSsL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg > /dev/null
  echo deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main | tee /etc/apt/sources.list.d/google-chrome.list
fi

#cp -r /usr/share/keyrings $SAVE_PATH

apt-get update && apt-get install -y $PKG_DOWNLOAD_LIST


rm -rf $SAVE_PATH/{apt-offline.sig,apt-offline.zip}

# apt-offline依赖python3（通过apt install 安装的apt-offline，运行时报错）
wget https://github.com/rickysarraf/apt-offline/releases/download/v1.8.5/apt-offline-1.8.5.tar.gz -O - | tar -zx
cd apt-offline
./apt-offline set --update --upgrade $SAVE_PATH/apt-offline.sig
./apt-offline set $SAVE_PATH/apt-offline.sig --install-packages $PKG_DOWNLOAD_LIST
./apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip
