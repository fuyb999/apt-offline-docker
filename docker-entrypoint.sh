#!/bin/bash

RESTORE='\033[0m'
RED='\033[00;31m'

SAVE_PATH=/tmp/debs
sed -i -E "s/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" /etc/apt/sources.list
apt-get update && apt install -y curl gpg apt-rdepends

chown -Rv _apt:root /var/cache/apt/archives/partial/

#IFS=',' read -ra elements <<< "$PKG_DOWNLOAD_LIST"
list=(${PKG_DOWNLOAD_LIST//,/ })
for pkg in ${list[@]}
do
  printf "$RED Download $pkg...\n$RESTORE"
  sleep 2
  mkdir -p $SAVE_PATH/$pkg
  cd $SAVE_PATH/$pkg

  if [ "$pkg" == "nvidia-container-toolkit" ]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
  fi

  apt-get download $(apt-rdepends $pkg | grep -v "^ " | grep -v "awk" | sed 's/debconf-2.0/debconf/g')
  cd -
done