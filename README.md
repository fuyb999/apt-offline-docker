# Ubuntu apt offline

## get apt-offline.zip
1. set the UBUNTU_VERSION environment variable in the .env file  
2. set the PKG_DOWNLOAD_LIST environment variable in the .env file  
3. get apt-offline.zip  
```shell
sudo docker-compose up
```

## install apt-offline.zip
```shell
tar -zxvf apt-offline-1.8.5.tar.gz
cd apt-offline
./apt-offline install <path>/apt-offline.zip
```