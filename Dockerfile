ARG UBUNTU_VERSION
FROM ubuntu:${UBUNTU_VERSION}

ENV SAVE_PATH=/tmp/output
RUN sed -i -E "s/(archive|security).ubuntu.com/mirrors.ustc.edu.cn/g" /etc/apt/sources.list

RUN apt-get update && \
    apt-get upgrade && \
    apt-get install -y bash curl gpg lsb-core software-properties-common && \
    # nvidia-container-toolkit
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list && \
    # docker-ce
    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | apt-key add - &&  \
    add-apt-repository "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable" && \
    # install apt-offline
    curl -fSsL https://github.com/rickysarraf/apt-offline/releases/download/v1.8.5/apt-offline-1.8.5.tar.gz -o - | tar --strip-components=1 -zx -C /usr/bin && \
    # uninstall
    apt-get purge -y curl gpg lsb-core software-properties-common && \
    apt-get autoremove -y

ADD docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

CMD ["/bin/sh", "/docker-entrypoint.sh"]
