#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="${repo_root}/scripts/generate-packages-index.sh"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT

package_root="${temporary_root}/package"
repository="${temporary_root}/repository"
mkdir -p "${package_root}/DEBIAN" "${package_root}/usr/share/example" "${repository}"

cat > "${package_root}/DEBIAN/control" <<'CONTROL'
Package: example-package
Version: 1.0.0
Section: misc
Priority: optional
Architecture: all
Maintainer: Aura Test <aura@example.invalid>
Description: Test package for repository index permissions
CONTROL

printf 'fixture\n' > "${package_root}/usr/share/example/payload"
dpkg-deb --build "${package_root}" "${repository}/example-package_1.0.0_all.deb" >/dev/null

umask 0022
bash "${generator}" "${repository}"

packages_mode="$(stat -c '%a' "${repository}/Packages")"
if [ "${packages_mode}" != "644" ]; then
  printf 'FAIL: Packages mode is %s, expected 644\n' "${packages_mode}" >&2
  exit 1
fi

printf 'PASS: repository indexes are host-readable\n'
