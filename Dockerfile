ARG UBUNTU_VERSION
ARG PKG_DOWNLOAD_LIST
FROM ubuntu:${UBUNTU_VERSION}

ENV SAVE_PATH=/tmp/debs
RUN sed -i -E "s/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g" /etc/apt/sources.list

RUN apt-get update && apt-get upgrade && apt-get install -y curl wget gpg lsb-core software-properties-common python3

RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
   && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
   sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
   tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

RUN curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | apt-key add - && \
  add-apt-repository "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"

RUN curl -fSsL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg > /dev/null && \
  echo deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main | tee \
  /etc/apt/sources.list.d/google-chrome.list

RUN apt-get update

RUN wget https://github.com/rickysarraf/apt-offline/releases/download/v1.8.5/apt-offline-1.8.5.tar.gz -O - | tar --strip-components=1 -zx -C /usr/bin

#RUN apt-get install -y ${PKG_DOWNLOAD_LIST}
RUN apt-get install -y bash git curl wget jq tar bzip2 zip unzip xz-utils rar unrar p7zip-full vim openssh-server net-tools build-essential g++ gcc make libglvnd-dev pkg-config cmake language-pack-zh-hans language-pack-zh-hans-base nvidia-container-toolkit docker-ce


ADD docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

CMD ["/bin/sh", "/docker-entrypoint.sh"]
