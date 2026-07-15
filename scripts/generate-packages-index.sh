#!/bin/bash

set -euo pipefail

repo_dir="${1:-}"

if [ -z "${repo_dir}" ]; then
  printf 'Usage: %s REPOSITORY_DIR\n' "${0##*/}" >&2
  exit 2
fi

if [ ! -d "${repo_dir}" ]; then
  printf 'Repository directory not found: %s\n' "${repo_dir}" >&2
  exit 1
fi

packages_file="${repo_dir}/Packages"
temporary_file="$(mktemp "${repo_dir}/.Packages.XXXXXX")"
trap 'rm -f "${temporary_file}"' EXIT

while IFS= read -r package_name; do
  package_path="${repo_dir}/${package_name}"

  dpkg-deb -f "${package_path}"
  printf 'Filename: ./%s\n' "${package_name}"
  printf 'Size: %s\n' "$(stat -c '%s' "${package_path}")"
  printf 'MD5sum: %s\n' "$(md5sum "${package_path}" | awk '{print $1}')"
  printf 'SHA1: %s\n' "$(sha1sum "${package_path}" | awk '{print $1}')"
  printf 'SHA256: %s\n' "$(sha256sum "${package_path}" | awk '{print $1}')"
  printf '\n'
done < <(find "${repo_dir}" -maxdepth 1 -type f -name '*.deb' -printf '%f\n' | LC_ALL=C sort) > "${temporary_file}"

if [ ! -s "${temporary_file}" ]; then
  printf 'No Debian packages found in %s\n' "${repo_dir}" >&2
  exit 1
fi

chmod 0644 "${temporary_file}"
mv "${temporary_file}" "${packages_file}"
gzip -n -9 -c "${packages_file}" > "${packages_file}.gz"

trap - EXIT
