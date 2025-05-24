#!/bin/bash

# apt-get update && apt-get upgrade && apt-get install -y $PKG_DOWNLOAD_LIST

SAVE_PATH=/tmp/
rm -rf $SAVE_PATH/* /etc/apt/sources.list.d/archive_uri-https_mirrors_ustc_edu_cn_docker-ce_linux_ubuntu-jammy.list

apt-get update && \
apt-get upgrade && \
  apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST && \
  apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip