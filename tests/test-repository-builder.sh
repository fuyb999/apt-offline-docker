#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="${repo_root}/Dockerfile"
entrypoint="${repo_root}/docker-entrypoint.sh"
compose_file="${repo_root}/docker-compose.yml"
env_file="${repo_root}/.env"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    grep -Fq -- "${pattern}" "${file}" || fail "${file#${repo_root}/} does not contain: ${pattern}"
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    if grep -Fiq -- "${pattern}" "${file}"; then
        fail "${file#${repo_root}/} unexpectedly contains: ${pattern}"
    fi
}

assert_contains "${dockerfile}" 'ARG CORE_IMAGE'
assert_contains "${dockerfile}" 'FROM ${CORE_IMAGE}'
assert_contains "${dockerfile}" 'repack-fcitx5-pinyin-runtime.sh'
assert_contains "${dockerfile}" 'generate-packages-index.sh'
assert_contains "${dockerfile}" 'build-node-runtime.sh'

for forbidden in pyinstaller apt-offline docker-ce nvidia-container-toolkit; do
    assert_not_contains "${dockerfile}" "${forbidden}"
done

assert_contains "${entrypoint}" '--download-only'
assert_contains "${entrypoint}" '--no-install-recommends'
assert_contains "${entrypoint}" 'repack-fcitx5-pinyin-runtime.sh'
assert_contains "${entrypoint}" 'generate-packages-index.sh'
assert_contains "${entrypoint}" 'apt-offline-gui-repo'
assert_contains "${entrypoint}" 'core-packages.lock'
assert_contains "${entrypoint}" 'CC_SWITCH_DEB_URL'
assert_contains "${entrypoint}" 'build-node-runtime.sh'
assert_contains "${entrypoint}" 'chown _apt:root "${source_dir}"'
assert_contains "${entrypoint}" 'dpkg-query'
assert_not_contains "${entrypoint}" 'apt-get -y upgrade'
assert_not_contains "${entrypoint}" 'apt-offline set'
assert_not_contains "${entrypoint}" 'tail -f /dev/null'

assert_contains "${compose_file}" 'CORE_IMAGE=${CORE_IMAGE}'
assert_contains "${compose_file}" './output:/output:rw'
assert_contains "${env_file}" 'CORE_IMAGE='
assert_contains "${env_file}" 'CC_SWITCH_VERSION=3.14.1'
assert_contains "${env_file}" 'NODE_VERSION=24.17.0'
assert_contains "${env_file}" 'NVM_VERSION=0.40.4'
assert_contains "${env_file}" 'NODE_DEFAULT_ENV=tools'
assert_contains "${env_file}" 'fcitx5-module-punctuation'
assert_contains "${env_file}" 'libimepinyin0'
assert_contains "${env_file}" 'build-essential'
assert_contains "${env_file}" 'libwebkit2gtk-4.1-0'
assert_contains "${env_file}" 'python3-venv'
packages_line="$(grep '^PKG_DOWNLOAD_LIST=' "${env_file}" || true)"
[ -n "${packages_line}" ] || fail 'PKG_DOWNLOAD_LIST is missing'
read -r -a configured_packages <<< "${packages_line#PKG_DOWNLOAD_LIST=}"

has_package() {
    local expected="$1"
    local configured=""

    for configured in "${configured_packages[@]}"; do
        [ "${configured}" = "${expected}" ] && return 0
    done
    return 1
}

for package in \
    at-spi2-core \
    avahi-utils \
    fcitx5-frontend-gtk2 \
    fcitx5-frontend-gtk3 \
    fcitx5-frontend-gtk4 \
    fonts-dejavu \
    fonts-firacode \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    fonts-wqy-microhei \
    i965-va-driver-shaders \
    intel-media-va-driver-non-free \
    iptables \
    libnspr4 \
    libnss3 \
    libpulse-mainloop-glib0 \
    libxfont2 \
    libpixman-1-0 \
    libxcb-image0 \
    libxcb-render-util0 \
    pipewire \
    rtkit \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    xdg-utils \
    xserver-xorg-video-intel; do
    has_package "${package}" || fail "PKG_DOWNLOAD_LIST is missing addon runtime dependency ${package}"
done

assert_not_contains "${env_file}" 'fcitx5-module-*'
assert_not_contains "${env_file}" 'fcitx5-chinese-addons '

bash -n "${entrypoint}"

printf 'PASS: offline repository builder contract\n'
