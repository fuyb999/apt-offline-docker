# Ubuntu apt offline

## get apt-offline.xz
1. set the UBUNTU_VERSION environment variable in the .env file  
2. set the PKG_DOWNLOAD_LIST environment variable in the .env file  
3. get apt-offline.xz  
```shell
sudo docker-compose build downloader
sudo docker-compose up
```

## offline install
```shell
tar -Jxvf apt-offline.tar.xz -C /
sudo apt-get update
```