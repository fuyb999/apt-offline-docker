#!/bin/bash

set -e

SAVE_PATH=/tmp
rm -rf $SAVE_PATH/* /etc/apt/sources.list.d/archive_uri-https_mirrors_ustc_edu_cn_docker-ce_linux_ubuntu-jammy.list

apt-get update && \
apt-get -y upgrade && \
  apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST && \
  apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip

apt-get install -y dpkg-dev unzip

unzip $SAVE_PATH/apt-offline.zip -d /tmp/apt-offline
cd /tmp/apt-offline/ && dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz && cd -

tee /etc/apt/sources.list.d/local.list << EOF
deb [trusted=yes] file:/tmp/apt-offline ./
EOF

tar -Jcvf /tmp/apt-offline-mirror.tar.xz /tmp/apt-offline/ /etc/apt/sources.list.d/local.list

tail -f /dev/null