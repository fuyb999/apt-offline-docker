#!/bin/bash

set -euo pipefail

source_deb="${1:-}"
output_dir="${2:-}"

if [ -z "${source_deb}" ] || [ -z "${output_dir}" ]; then
  printf 'Usage: %s FCITX5_PINYIN_DEB OUTPUT_DIR\n' "${0##*/}" >&2
  exit 2
fi

if [ ! -f "${source_deb}" ]; then
  printf 'Source package not found: %s\n' "${source_deb}" >&2
  exit 1
fi

mkdir -p "${output_dir}"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

package_root="${work_dir}/package"
dpkg-deb -R "${source_deb}" "${package_root}"

engine_path="$(find "${package_root}/usr/lib" -type f -path '*/fcitx5/libpinyin.so' -print -quit 2> /dev/null || true)"
if [ -z "${engine_path}" ]; then
  printf 'Source package does not contain the native pinyin engine\n' >&2
  exit 1
fi

find "${package_root}/usr/lib" -type f -path '*/fcitx5/qt5/libpinyindictmanager.so' -delete
find "${package_root}/usr/lib" -type d -empty -delete

control_file="${package_root}/DEBIAN/control"
original_version="$(dpkg-deb -f "${source_deb}" Version)"
architecture="$(dpkg-deb -f "${source_deb}" Architecture)"
original_depends="$(dpkg-deb -f "${source_deb}" Depends)"
runtime_version="${original_version}+aura1"

runtime_depends="$(
  printf '%s\n' "${original_depends}" \
    | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk '
        /^libfcitx5-qt1([[:space:](]|$)/ { next }
        /^libqt5/ { next }
        NF { print }
      ' \
    | awk '
        BEGIN { separator = "" }
        {
          printf "%s%s", separator, $0
          separator = ", "
        }
        END { print "" }
      '
)"

if [ -z "${runtime_depends}" ]; then
  printf 'Failed to derive runtime dependencies from %s\n' "${source_deb}" >&2
  exit 1
fi

installed_size="$(du -sk --exclude=DEBIAN "${package_root}" | awk '{print $1}')"
updated_control="${work_dir}/control"

awk \
  -v package='fcitx5-pinyin-runtime' \
  -v version="${runtime_version}" \
  -v installed_size="${installed_size}" \
  -v depends="${runtime_depends}" '
    function starts_replaced_field(line) {
      return line ~ /^(Package|Version|Installed-Size|Depends|Provides|Conflicts|Replaces|Recommends):/
    }

    /^[^[:space:]][^:]*:/ {
      skipping = starts_replaced_field($0)
    }

    skipping {
      next
    }

    {
      print
    }

    END {
      print "Package: " package
      print "Version: " version
      print "Installed-Size: " installed_size
      print "Depends: " depends
      print "Provides: fcitx5-pinyin"
      print "Conflicts: fcitx5-pinyin"
      print "Replaces: fcitx5-pinyin"
    }
  ' "${control_file}" > "${updated_control}"

mv "${updated_control}" "${control_file}"

safe_version="${runtime_version//:/%3a}"
output_deb="${output_dir}/fcitx5-pinyin-runtime_${safe_version}_${architecture}.deb"
dpkg-deb --build --root-owner-group "${package_root}" "${output_deb}" > /dev/null

printf '%s\n' "${output_deb}"
