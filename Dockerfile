# 第一阶段：构建 apt-offline
FROM pschmitt/pyinstaller:3.10 AS pyinstaller

RUN apt-get update && \
    apt-get install -y curl tar pyqt5-dev-tools man2html-base python3-debianbts libmagic-dev

RUN pip install argparse soappy pylzma pysimplesoap

WORKDIR /app/apt-offline
RUN curl -fSsL https://github.com/rickysarraf/apt-offline/releases/download/v1.8.6/apt-offline-1.8.6.tar.gz | \
    tar --strip-components=1 -zxvf - -C ./ && \
    mv apt-offline apt-offline.py && \
    rm -f requirements.txt && \
    sed -i -E 's|(.*LoadLibrary)\(.*\)(.*)|\1\("/usr/local/lib/libmagic.so.1.0.0"\)\2|g' ./apt_offline_core/AptOfflineMagicLib.py


RUN /entrypoint.sh \
#    --add-binary "/usr/lib/x86_64-linux-gnu/libmagic.so.1.0.0:./" \
    /app/apt-offline/apt-offline.py

RUN ls /app/dist -l


RUN chmod +x /app/dist/apt-offline



# 第二阶段：设置镜像源
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION:-22.04} AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get upgrade && \
    apt-get install -y bash curl gpg lsb-core software-properties-common

RUN true && \
    # nvidia-container-toolkit
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --batch --no-tty --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list && \
    # docker-ce
    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | \
    gpg --batch --no-tty --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list

# 第三阶段：最终镜像
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION:-22.04}

COPY --from=pyinstaller /app/dist/apt-offline /usr/bin
COPY --from=pyinstaller /usr/lib/x86_64-linux-gnu/libmagic.so.1.0.0 /usr/local/lib/

COPY --from=builder /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg /usr/share/keyrings/
COPY --from=builder /usr/share/keyrings/docker-archive-keyring.gpg /usr/share/keyrings/
#COPY --from=builder /etc/apt/trusted.gpg.d/nvidia-container-toolkit-keyring.gpg /etc/apt/trusted.gpg.d/
#COPY --from=builder /etc/apt/trusted.gpg.d/docker-archive-keyring.gpg /etc/apt/trusted.gpg.d/
COPY --from=builder /etc/apt/sources.list.d/nvidia-container-toolkit.list /etc/apt/sources.list.d/
COPY --from=builder /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/

ADD docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

CMD ["/bin/sh", "/docker-entrypoint.sh"]



