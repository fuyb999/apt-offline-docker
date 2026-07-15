#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repack_script="${repo_root}/scripts/repack-fcitx5-pinyin-runtime.sh"

[ -x "${repack_script}" ] || {
    printf 'FAIL: missing executable %s\n' "${repack_script#${repo_root}/}" >&2
    exit 1
}

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

source_root="${test_root}/source"
output_dir="${test_root}/output"
mkdir -p \
    "${source_root}/DEBIAN" \
    "${source_root}/usr/lib/x86_64-linux-gnu/fcitx5/qt5" \
    "${source_root}/usr/lib/x86_64-linux-gnu/fcitx5" \
    "${source_root}/usr/share/fcitx5/pinyin" \
    "${output_dir}"

cat > "${source_root}/DEBIAN/control" <<'EOF'
Package: fcitx5-pinyin
Version: 5.0.11-1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Test Maintainer <test@example.com>
Installed-Size: 894
Depends: fcitx5-chinese-addons-data, fcitx5-module-punctuation (= 5.0.11-1), libboost-iostreams1.74.0 (>= 1.74.0), libc6 (>= 2.32), libfcitx5-qt1 (>= 5.0.10), libfcitx5config6 (>= 5.0.14), libfcitx5core7 (>= 5.0.14), libfcitx5utils2 (>= 5.0.14), libgcc-s1 (>= 3.3.1), libimecore0 (>= 1.0.11), libimepinyin0 (>= 1.0.11), libqt5core5a (>= 5.15.1), libqt5gui5 (>= 5.7.0) | libqt5gui5-gles (>= 5.7.0), libqt5network5 (>= 5.0.2), libqt5webenginewidgets5 (>= 5.7.1), libqt5widgets5 (>= 5.0.2), libstdc++6 (>= 11)
Recommends: fcitx5-module-cloudpinyin, fcitx5-module-quickphrase
Description: Fcitx5 native pinyin input method
 Native pinyin engine and graphical dictionary manager.
EOF

printf 'native engine\n' > "${source_root}/usr/lib/x86_64-linux-gnu/fcitx5/libpinyin.so"
printf 'webengine dictionary manager\n' > "${source_root}/usr/lib/x86_64-linux-gnu/fcitx5/qt5/libpinyindictmanager.so"
printf 'emoji data\n' > "${source_root}/usr/share/fcitx5/pinyin/emoji.dict"

source_deb="${test_root}/fcitx5-pinyin_5.0.11-1_amd64.deb"
dpkg-deb --build --root-owner-group "${source_root}" "${source_deb}" >/dev/null

runtime_deb="$("${repack_script}" "${source_deb}" "${output_dir}")"
[ -f "${runtime_deb}" ] || {
    printf 'FAIL: runtime package was not created\n' >&2
    exit 1
}

[ "$(dpkg-deb -f "${runtime_deb}" Package)" = 'fcitx5-pinyin-runtime' ]
[ "$(dpkg-deb -f "${runtime_deb}" Provides)" = 'fcitx5-pinyin' ]
[ "$(dpkg-deb -f "${runtime_deb}" Conflicts)" = 'fcitx5-pinyin' ]
[ "$(dpkg-deb -f "${runtime_deb}" Replaces)" = 'fcitx5-pinyin' ]

depends="$(dpkg-deb -f "${runtime_deb}" Depends)"
case "${depends}" in
    *libqt5*|*libfcitx5-qt1*|*webengine*)
        printf 'FAIL: runtime package retained GUI dependencies: %s\n' "${depends}" >&2
        exit 1
        ;;
esac

runtime_root="${test_root}/runtime"
dpkg-deb -x "${runtime_deb}" "${runtime_root}"
[ -f "${runtime_root}/usr/lib/x86_64-linux-gnu/fcitx5/libpinyin.so" ]
[ ! -e "${runtime_root}/usr/lib/x86_64-linux-gnu/fcitx5/qt5/libpinyindictmanager.so" ]
[ -f "${runtime_root}/usr/share/fcitx5/pinyin/emoji.dict" ]

printf 'PASS: fcitx5 native pinyin runtime repackaging\n'
