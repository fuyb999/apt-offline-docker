#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder="${repo_root}/scripts/build-node-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -x "${builder}" ] || fail 'scripts/build-node-runtime.sh is missing or not executable'

test_root="$(mktemp -d)"
cleanup() {
  rm -rf "${test_root}"
}
trap cleanup EXIT

nvm_source="${test_root}/nvm-0.40.4"
node_source="${test_root}/node-v24.17.0-linux-x64"
output_dir="${test_root}/output"
mkdir -p "${nvm_source}" "${node_source}/bin" "${output_dir}"

printf '%s\n' '# fake nvm' > "${nvm_source}/nvm.sh"
tar -czf "${test_root}/nvm.tar.gz" -C "${test_root}" "$(basename "${nvm_source}")"

cat > "${node_source}/bin/node" <<'NODE'
#!/bin/bash
printf 'v24.17.0\n'
NODE
cat > "${node_source}/bin/npm" <<'NPM'
#!/bin/bash
set -euo pipefail
prefix=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--prefix" ]; then
    prefix="$2"
    shift 2
  else
    shift
  fi
done
[ -n "${prefix}" ]
mkdir -p "${prefix}/bin" "${prefix}/lib/node_modules"
for command_name in pnpm opencode codex claude ccr; do
  printf '#!/bin/bash\nexit 0\n' > "${prefix}/bin/${command_name}"
  chmod 0755 "${prefix}/bin/${command_name}"
done
NPM
chmod 0755 "${node_source}/bin/node" "${node_source}/bin/npm"
tar -cJf "${test_root}/node.tar.xz" -C "${test_root}" "$(basename "${node_source}")"

NODE_VERSION=24.17.0 \
NVM_VERSION=0.40.4 \
NODE_DEFAULT_ENV=tools \
PNPM_VERSION=10.33.0 \
OPENCODE_VERSION=1.17.20 \
CODEX_VERSION=0.144.4 \
CLAUDE_CODE_VERSION=2.1.153 \
CLAUDE_CODE_ROUTER_VERSION=3.0.4 \
NVM_ARCHIVE_URL="${test_root}/nvm.tar.gz" \
NODE_ARCHIVE_URL="${test_root}/node.tar.xz" \
  "${builder}" "${output_dir}"

for output_file in \
  "nvm-v0.40.4.tar.gz" \
  "node-v24.17.0-linux-x64.tar.xz" \
  "node-tools.tar.xz" \
  "node-tools.packages" \
  "manifest.env"; do
  [ -s "${output_dir}/${output_file}" ] || fail "missing ${output_file}"
done

grep -Fqx 'pnpm@10.33.0' "${output_dir}/node-tools.packages"
grep -Fqx 'opencode-ai@1.17.20' "${output_dir}/node-tools.packages"
grep -Fqx '@openai/codex@0.144.4' "${output_dir}/node-tools.packages"
grep -Fqx '@anthropic-ai/claude-code@2.1.153' "${output_dir}/node-tools.packages"
grep -Fqx '@musistudio/claude-code-router@3.0.4' "${output_dir}/node-tools.packages"

for key in NVM_SHA256 NODE_SHA256 NODE_TOOLS_SHA256 PACKAGE_SET_SHA256; do
  grep -Eq "^${key}=[0-9a-f]{64}$" "${output_dir}/manifest.env" || fail "manifest is missing ${key}"
done

tools_extract="${test_root}/tools"
mkdir -p "${tools_extract}"
tar -Jxf "${output_dir}/node-tools.tar.xz" -C "${tools_extract}"
for command_name in pnpm opencode codex claude ccr; do
  [ -x "${tools_extract}/bin/${command_name}" ] || fail "tools archive is missing ${command_name}"
done

printf 'PASS: offline Node runtime builder\n'
