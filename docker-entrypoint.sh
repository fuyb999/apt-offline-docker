#!/bin/bash

SAVE_PATH=/tmp
rm -rf $SAVE_PATH/* /etc/apt/sources.list.d/archive_uri-https_mirrors_ustc_edu_cn_docker-ce_linux_ubuntu-jammy.list

apt-get update && \
apt-get upgrade && \
  apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST && \
  apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip
#  tar -czvf $SAVE_PATH/apt-offline.tar.gz \
#    /usr/bin/apt-offline \
#    /usr/share/misc/magic \
#    /usr/share/misc/magic.mgc \
#    /usr/lib/x86_64-linux-gnu/libmagic.so.1 \
#    /usr/lib/x86_64-linux-gnu/libmagic.so.1.0.0 \
#    $SAVE_PATH/apt-offline.sig \
#    $SAVE_PATH/apt-offline.zip \
#    /etc/apt/trusted.gpg.d/*.gpg \
#    /usr/share/keyrings/*.gpg

apt-get install -y dpkg-dev unzip
unzip $SAVE_PATH/apt-offline.zip -d /tmp/apt-offline
cd /tmp/apt-offline/ && dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz && cd -
tee /etc/apt/sources.list.d/local.list << EOF
deb [trusted=yes] file:/tmp/apt-offline ./
EOF
tar -zcvf /tmp/apt-offline.tar.gz /tmp/apt-offline/ /etc/apt/sources.list.d/local.list

tail -f /dev/null