#!/bin/bash

# apt-get update && apt-get upgrade && apt-get install -y $PKG_DOWNLOAD_LIST

SAVE_PATH=/tmp/output
rm -rf $SAVE_PATH/*

apt-get update && \
  apt-get install -y python3 && \
  apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST && \
  apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip