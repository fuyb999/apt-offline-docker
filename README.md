# Ubuntu apt offline

## get apt-offline.zip
1. set the UBUNTU_VERSION environment variable in the .env file  
2. set the PKG_DOWNLOAD_LIST environment variable in the .env file  
3. get apt-offline.zip  
```shell
sudo docker-compose build downloader
sudo docker-compose up
```

## offline install
```shell
sudo tar -zxvf apt-offline.tar.gz -C /
sudo apt-offline install --extra-keyring /usr/share/keyrings/ /tmp/apt-offline.zip
```