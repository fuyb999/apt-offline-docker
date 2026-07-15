#!/bin/bash

set -euo pipefail

output_dir="${1:-}"

if [ -z "${output_dir}" ]; then
  printf 'Usage: %s OUTPUT_DIR\n' "${0##*/}" >&2
  exit 2
fi

required_variables=(
  NODE_VERSION
  NVM_VERSION
  NODE_DEFAULT_ENV
  PNPM_VERSION
  OPENCODE_VERSION
  CODEX_VERSION
  CLAUDE_CODE_VERSION
  CLAUDE_CODE_ROUTER_VERSION
  NVM_ARCHIVE_URL
  NODE_ARCHIVE_URL
)
for variable_name in "${required_variables[@]}"; do
  if [ -z "${!variable_name:-}" ]; then
    printf '%s is required\n' "${variable_name}" >&2
    exit 2
  fi
done

download_source() {
  local source="$1"
  local destination="$2"

  if [ -f "${source}" ]; then
    cp -f "${source}" "${destination}"
  else
    curl -fL --retry 3 "${source}" -o "${destination}"
  fi
}

rm -rf "${output_dir}"
install -d -m 0755 "${output_dir}"

nvm_archive="${output_dir}/nvm-v${NVM_VERSION}.tar.gz"
node_archive="${output_dir}/node-v${NODE_VERSION}-linux-x64.tar.xz"
tools_archive="${output_dir}/node-tools.tar.xz"
packages_file="${output_dir}/node-tools.packages"
manifest_file="${output_dir}/manifest.env"

download_source "${NVM_ARCHIVE_URL}" "${nvm_archive}"
download_source "${NODE_ARCHIVE_URL}" "${node_archive}"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

node_root="${work_dir}/node"
tools_root="${work_dir}/${NODE_DEFAULT_ENV}"
npm_cache="${work_dir}/npm-cache"
mkdir -p "${node_root}" "${tools_root}" "${npm_cache}"
tar -Jxf "${node_archive}" --strip-components=1 -C "${node_root}"

if [ "$("${node_root}/bin/node" --version)" != "v${NODE_VERSION}" ]; then
  printf 'Downloaded Node archive did not provide v%s\n' "${NODE_VERSION}" >&2
  exit 1
fi
if [ ! -x "${node_root}/bin/npm" ]; then
  printf 'Downloaded Node archive does not contain npm\n' >&2
  exit 1
fi

tool_packages=(
  "pnpm@${PNPM_VERSION}"
  "opencode-ai@${OPENCODE_VERSION}"
  "@openai/codex@${CODEX_VERSION}"
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
  "@musistudio/claude-code-router@${CLAUDE_CODE_ROUTER_VERSION}"
)
printf '%s\n' "${tool_packages[@]}" > "${packages_file}"

PATH="${node_root}/bin:${PATH}" \
NPM_CONFIG_CACHE="${npm_cache}" \
  "${node_root}/bin/npm" install \
    --global \
    --prefix "${tools_root}" \
    --no-audit \
    --no-fund \
    "${tool_packages[@]}"

for command_name in pnpm opencode codex claude ccr; do
  if [ ! -e "${tools_root}/bin/${command_name}" ]; then
    printf 'Installed Node tools are missing bin/%s\n' "${command_name}" >&2
    exit 1
  fi
done

tar -cJf "${tools_archive}" -C "${tools_root}" .

{
  printf 'NODE_VERSION=%s\n' "${NODE_VERSION}"
  printf 'NVM_VERSION=%s\n' "${NVM_VERSION}"
  printf 'NODE_DEFAULT_ENV=%s\n' "${NODE_DEFAULT_ENV}"
  printf 'NVM_SHA256=%s\n' "$(sha256sum "${nvm_archive}" | awk '{print $1}')"
  printf 'NODE_SHA256=%s\n' "$(sha256sum "${node_archive}" | awk '{print $1}')"
  printf 'NODE_TOOLS_SHA256=%s\n' "$(sha256sum "${tools_archive}" | awk '{print $1}')"
  printf 'PACKAGE_SET_SHA256=%s\n' "$(sha256sum "${packages_file}" | awk '{print $1}')"
  printf 'GENERATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${manifest_file}"

printf 'Created offline Node %s environment %s at %s\n' \
  "${NODE_VERSION}" "${NODE_DEFAULT_ENV}" "${output_dir}"

trap - EXIT
cleanup
