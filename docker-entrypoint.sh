#!/bin/bash

set -euo pipefail

output_root="${OUTPUT_ROOT:-/output}"
repo_dir="${output_root}/apt-offline-gui-repo"
node_runtime_dir="${output_root}/node-runtime"
source_package="${PINYIN_SOURCE_PACKAGE:-fcitx5-pinyin}"

for variable_name in PKG_DOWNLOAD_LIST CC_SWITCH_VERSION CC_SWITCH_DEB_URL; do
  if [ -z "${!variable_name:-}" ]; then
    printf '%s is required\n' "${variable_name}" >&2
    exit 2
  fi
done

read -r -a packages <<< "${PKG_DOWNLOAD_LIST}"
if [ "${#packages[@]}" -eq 0 ]; then
  printf 'PKG_DOWNLOAD_LIST did not contain any packages\n' >&2
  exit 2
fi

rm -rf "${repo_dir}"
install -d -m 0755 "${repo_dir}"
install -d -m 0700 -o _apt -g root "${repo_dir}/partial"

dpkg-query -W -f='${binary:Package}=${Version}\n' \
  | LC_ALL=C sort \
  > "${repo_dir}/core-packages.lock"

printf 'Refreshing package metadata for %s\n' "${CORE_IMAGE:-the configured core image}"
apt-get update

cc_switch_deb="${repo_dir}/cc-switch_${CC_SWITCH_VERSION}_amd64.deb"
cc_switch_package_matches() {
  local package_path="$1"

  [ -f "${package_path}" ] || return 1
  [ "$(dpkg-deb -f "${package_path}" Package 2>/dev/null)" = "cc-switch" ] || return 1
  [ "$(dpkg-deb -f "${package_path}" Version 2>/dev/null)" = "${CC_SWITCH_VERSION}" ]
}

if cc_switch_package_matches "${cc_switch_deb}"; then
  printf 'Reusing cached CC Switch %s\n' "${CC_SWITCH_VERSION}"
else
  rm -f -- "${cc_switch_deb}"
  printf 'Downloading CC Switch %s\n' "${CC_SWITCH_VERSION}"
  curl -fL --retry 3 "${CC_SWITCH_DEB_URL}" -o "${cc_switch_deb}"
  if ! cc_switch_package_matches "${cc_switch_deb}"; then
    printf 'Downloaded CC Switch package metadata does not match %s\n' "${CC_SWITCH_VERSION}" >&2
    exit 1
  fi
fi

printf 'Downloading GUI, development and CC Switch dependency closure\n'
apt-get install \
  --download-only \
  --no-install-recommends \
  -y \
  -o "Dir::Cache::archives=${repo_dir}" \
  "${packages[@]}" \
  "${cc_switch_deb}"

source_dir="$(mktemp -d)"
chown _apt:root "${source_dir}"
cleanup() {
  rm -rf "${source_dir}"
}
trap cleanup EXIT

(
  cd "${source_dir}"
  apt-get download "${source_package}"
)

source_deb="$(find "${source_dir}" -maxdepth 1 -type f -name 'fcitx5-pinyin_*.deb' -print -quit)"
if [ -z "${source_deb}" ]; then
  printf 'Unable to download %s\n' "${source_package}" >&2
  exit 1
fi

repack-fcitx5-pinyin-runtime.sh "${source_deb}" "${repo_dir}" > /dev/null
rm -rf "${repo_dir}/partial" "${repo_dir}/lock"

generate-packages-index.sh "${repo_dir}"

printf '%s\n' "${packages[@]}" > "${repo_dir}/download-packages.txt"
printf '%s\n' cc-switch >> "${repo_dir}/download-packages.txt"
{
  printf 'CORE_IMAGE=%s\n' "${CORE_IMAGE:-unknown}"
  printf 'PINYIN_SOURCE_PACKAGE=%s\n' "${source_package}"
  printf 'CC_SWITCH_VERSION=%s\n' "${CC_SWITCH_VERSION}"
  printf 'PACKAGE_SET_SHA256=%s\n' "$(sha256sum "${repo_dir}/download-packages.txt" | awk '{print $1}')"
  printf 'GENERATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${repo_dir}/manifest.env"

package_count="$(find "${repo_dir}" -maxdepth 1 -type f -name '*.deb' | wc -l)"
repo_size="$(du -sh "${repo_dir}" | awk '{print $1}')"
printf 'Created %s with %s packages (%s)\n' "${repo_dir}" "${package_count}" "${repo_size}"

trap - EXIT
cleanup

build-node-runtime.sh "${node_runtime_dir}"
