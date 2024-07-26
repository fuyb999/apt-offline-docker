#!/bin/bash

# apt-get update && apt-get upgrade && apt-get install -y $PKG_DOWNLOAD_LIST

rm -rf $SAVE_PATH/{apt-offline.sig,apt-offline.zip}

apt-offline set --update --upgrade $SAVE_PATH/apt-offline.sig
apt-offline set $SAVE_PATH/apt-offline.sig --update --upgrade --install-packages $PKG_DOWNLOAD_LIST
apt-offline get $SAVE_PATH/apt-offline.sig --bundle $SAVE_PATH/apt-offline.zip
