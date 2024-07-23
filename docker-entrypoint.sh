#!/bin/bash

RESTORE='\033[0m'
RED='\033[00;31m'

SAVE_PATH=/tmp/debs
sed -i -E "s/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" /etc/apt/sources.list
apt-get update && apt install -y curl wget gpg python2

list=(${PKG_DOWNLOAD_LIST// / })
for pkg in ${list[@]}
do
  printf "$RED install $pkg...\n$RESTORE"
  if [ "$pkg" == "nvidia-container-toolkit" ]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
  fi
  apt-get install -y $pkg
done

rm -rf $SAVE_PATH/{apt-offline.sig,apt-offline.zip}
# apt-offline在python2上运行正常，不可通过apt install
wget https://github.com/rickysarraf/apt-offline/releases/download/v1.8.5/apt-offline-1.8.5.tar.gz -O - | tar -zx
cd apt-offline
./apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST
./apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip
cd -