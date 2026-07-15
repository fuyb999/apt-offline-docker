ARG CORE_IMAGE=ubuntu:22.04
FROM ${CORE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive

COPY scripts/repack-fcitx5-pinyin-runtime.sh /usr/local/bin/repack-fcitx5-pinyin-runtime.sh
COPY scripts/generate-packages-index.sh /usr/local/bin/generate-packages-index.sh
COPY scripts/build-node-runtime.sh /usr/local/bin/build-node-runtime.sh
COPY docker-entrypoint.sh /usr/local/bin/build-offline-gui-repo

RUN chmod +x \
    /usr/local/bin/repack-fcitx5-pinyin-runtime.sh \
    /usr/local/bin/generate-packages-index.sh \
    /usr/local/bin/build-node-runtime.sh \
    /usr/local/bin/build-offline-gui-repo

ENTRYPOINT ["/usr/local/bin/build-offline-gui-repo"]
