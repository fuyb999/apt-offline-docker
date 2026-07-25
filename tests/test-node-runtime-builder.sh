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
bun_source="${test_root}/bun-linux-x64"
symlink_bun_source="${test_root}/symlink-source/bun-linux-x64"
output_dir="${test_root}/output"
fixture_bin="${test_root}/bin"
mkdir -p \
  "${nvm_source}" \
  "${node_source}/bin" \
  "${bun_source}" \
  "${symlink_bun_source}" \
  "${output_dir}" \
  "${fixture_bin}"

cat > "${fixture_bin}/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'fixture download failure: %s\n' "${!#}" >&2
exit 44
EOF
cat > "${fixture_bin}/tar" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${FIXTURE_ARCHIVE_PROBE:-}" ]; then
  printf 'tar\n' >> "${FIXTURE_ARCHIVE_PROBE}"
fi
exec /usr/bin/tar "$@"
EOF
cat > "${fixture_bin}/unzip" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${FIXTURE_ARCHIVE_PROBE:-}" ]; then
  printf 'unzip\n' >> "${FIXTURE_ARCHIVE_PROBE}"
fi
exec /usr/bin/unzip "$@"
EOF
cat > "${fixture_bin}/zipinfo" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${FIXTURE_ARCHIVE_PROBE:-}" ]; then
  printf 'zipinfo\n' >> "${FIXTURE_ARCHIVE_PROBE}"
fi
exec /usr/bin/zipinfo "$@"
EOF
cat > "${fixture_bin}/ln" <<'EOF'
#!/bin/bash
set -euo pipefail
destination=""
if [ "${FIXTURE_BAD_BUNX:-0}" = 1 ] && [ "$1" = -s ]; then
  if [ "$#" -eq 3 ] && [ "$2" = bun ]; then
    destination="$3"
  elif [ "$#" -eq 4 ] && [ "$2" = -- ] && [ "$3" = bun ]; then
    destination="$4"
  fi
fi
if [ -n "${destination}" ]; then
  cat > "${destination}" <<'BUNX'
#!/bin/bash
printf '1.3.13\n'
BUNX
  chmod 0755 "${destination}"
  exit 0
fi
exec /usr/bin/ln "$@"
EOF
cat > "${fixture_bin}/mv" <<'EOF'
#!/bin/bash
set -euo pipefail
source_path="${@: -2:1}"
destination="${!#}"
if [ "${FIXTURE_FAIL_PUBLISH_MV:-0}" = 1 ] && \
  [[ "${source_path}" == *'.staging.'*'/output' ]] && \
  [ "${destination}" = "${FIXTURE_OUTPUT_DIR}" ]; then
  printf 'fixture publish mv failure: %s\n' "${destination}" >&2
  exit 76
fi
exec /usr/bin/mv "$@"
EOF
cat > "${fixture_bin}/install" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${FIXTURE_FAIL_STAGING_INSTALL:-0}" = 1 ]; then
  for argument in "$@"; do
    if [[ "${argument}" == *'.staging.'* ]]; then
      printf 'fixture staging install failure: %s\n' "${argument}" >&2
      exit 79
    fi
  done
fi
exec /usr/bin/install "$@"
EOF
chmod 0755 \
  "${fixture_bin}/curl" \
  "${fixture_bin}/install" \
  "${fixture_bin}/ln" \
  "${fixture_bin}/mv" \
  "${fixture_bin}/tar" \
  "${fixture_bin}/unzip" \
  "${fixture_bin}/zipinfo"

printf '%s\n' '# fake nvm' > "${nvm_source}/nvm.sh"
tar -czf "${test_root}/nvm.tar.gz" -C "${test_root}" "$(basename "${nvm_source}")"

cat > "${node_source}/bin/node" <<'NODE'
#!/bin/bash
if [ -n "${FIXTURE_NODE_EXEC_PROBE:-}" ]; then
  printf 'node\n' >> "${FIXTURE_NODE_EXEC_PROBE}"
fi
printf '%s\n' "${FIXTURE_NODE_REPORTED_VERSION:-v24.17.0}"
NODE
cat > "${node_source}/bin/npm" <<'NPM'
#!/bin/bash
set -euo pipefail
if [ -n "${FIXTURE_NPM_EXEC_PROBE:-}" ]; then
  printf 'npm\n' >> "${FIXTURE_NPM_EXEC_PROBE}"
fi
if [ "${FIXTURE_NPM_FAIL:-0}" = 1 ]; then
  printf 'fixture npm failure\n' >&2
  exit 42
fi
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

cat > "${bun_source}/bun" <<'BUN'
#!/bin/bash
if [ -n "${FIXTURE_BUN_EXEC_PROBE:-}" ]; then
  printf 'bun\n' >> "${FIXTURE_BUN_EXEC_PROBE}"
fi
printf '%s\n' "${FIXTURE_BUN_REPORTED_VERSION:-1.3.14}"
BUN
chmod 0755 "${bun_source}/bun"
(
  cd "${test_root}"
  zip -qr "${test_root}/bun.zip" "$(basename "${bun_source}")"
)
ln -s target "${symlink_bun_source}/bun"
(
  cd "${test_root}/symlink-source"
  zip -qry "${test_root}/bun-symlink.zip" bun-linux-x64
)

nvm_archive_sha256="$(sha256sum "${test_root}/nvm.tar.gz" | awk '{print $1}')"
node_archive_sha256="$(sha256sum "${test_root}/node.tar.xz" | awk '{print $1}')"
bun_archive_sha256="$(sha256sum "${test_root}/bun.zip" | awk '{print $1}')"
symlink_bun_archive_sha256="$(sha256sum "${test_root}/bun-symlink.zip" | awk '{print $1}')"

builder_variables=(
  NODE_VERSION
  NVM_VERSION
  NODE_DEFAULT_ENV
  BUN_VERSION
  PNPM_VERSION
  OPENCODE_VERSION
  CODEX_VERSION
  CLAUDE_CODE_VERSION
  CLAUDE_CODE_ROUTER_VERSION
  NVM_ARCHIVE_URL
  NODE_ARCHIVE_URL
  BUN_ARCHIVE_URL
  NVM_ARCHIVE_SHA256
  NODE_ARCHIVE_SHA256
  BUN_ARCHIVE_SHA256
)
for variable_name in "${builder_variables[@]}"; do
  unset "${variable_name}"
done

run_builder() {
  local builder_output_dir="$1"

  PATH="${fixture_bin}:/usr/bin:/bin" \
  NODE_VERSION="${NODE_VERSION-24.17.0}" \
  NVM_VERSION="${NVM_VERSION-0.40.4}" \
  NODE_DEFAULT_ENV="${NODE_DEFAULT_ENV-tools}" \
  BUN_VERSION="${BUN_VERSION-1.3.14}" \
  PNPM_VERSION="${PNPM_VERSION-10.33.0}" \
  OPENCODE_VERSION="${OPENCODE_VERSION-1.17.20}" \
  CODEX_VERSION="${CODEX_VERSION-0.144.4}" \
  CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION-2.1.153}" \
  CLAUDE_CODE_ROUTER_VERSION="${CLAUDE_CODE_ROUTER_VERSION-3.0.4}" \
  NVM_ARCHIVE_URL="${NVM_ARCHIVE_URL-${test_root}/nvm.tar.gz}" \
  NODE_ARCHIVE_URL="${NODE_ARCHIVE_URL-${test_root}/node.tar.xz}" \
  BUN_ARCHIVE_URL="${BUN_ARCHIVE_URL-${test_root}/bun.zip}" \
  NVM_ARCHIVE_SHA256="${NVM_ARCHIVE_SHA256-${nvm_archive_sha256}}" \
  NODE_ARCHIVE_SHA256="${NODE_ARCHIVE_SHA256-${node_archive_sha256}}" \
  BUN_ARCHIVE_SHA256="${BUN_ARCHIVE_SHA256-${bun_archive_sha256}}" \
    "${builder}" "${builder_output_dir}"
}

run_builder_with_override() {
  local variable_name="$1"
  local value="$2"
  local builder_output_dir="$3"

  (
    export "${variable_name}=${value}"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_sha_probe() {
  local variable_name="$1"
  local value="$2"
  local builder_output_dir="$3"
  local probe_prefix="$4"

  (
    export "${variable_name}=${value}"
    export FIXTURE_ARCHIVE_PROBE="${probe_prefix}.archive"
    export FIXTURE_NODE_EXEC_PROBE="${probe_prefix}.node"
    export FIXTURE_BUN_EXEC_PROBE="${probe_prefix}.bun"
    export FIXTURE_NPM_EXEC_PROBE="${probe_prefix}.npm"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_success_probes() {
  local builder_output_dir="$1"
  local probe_prefix="$2"

  (
    export FIXTURE_ARCHIVE_PROBE="${probe_prefix}.archive"
    export FIXTURE_NODE_EXEC_PROBE="${probe_prefix}.node"
    export FIXTURE_BUN_EXEC_PROBE="${probe_prefix}.bun"
    export FIXTURE_NPM_EXEC_PROBE="${probe_prefix}.npm"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_download_failure() {
  local variable_name="$1"
  local builder_output_dir="$2"

  (
    export "${variable_name}=missing://${variable_name}"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_fixture() {
  local variable_name="$1"
  local value="$2"
  local builder_output_dir="$3"

  (
    export "${variable_name}=${value}"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_symlink_archive() {
  local builder_output_dir="$1"

  (
    export BUN_ARCHIVE_URL="${test_root}/bun-symlink.zip"
    export BUN_ARCHIVE_SHA256="${symlink_bun_archive_sha256}"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_publish_failure() {
  local builder_output_dir="$1"

  (
    export FIXTURE_FAIL_PUBLISH_MV=1
    export FIXTURE_OUTPUT_DIR="${builder_output_dir}"
    run_builder "${builder_output_dir}"
  )
}

run_builder_with_staging_install_failure() {
  local builder_output_dir="$1"

  (
    export FIXTURE_FAIL_STAGING_INSTALL=1
    run_builder "${builder_output_dir}"
  )
}

seed_existing_output() {
  local directory="$1"
  local snapshot="$2"

  rm -rf -- "${directory}" "${snapshot}" "${snapshot}.entries" "${snapshot}.actual-entries"
  mkdir -p -- "${directory}" "${snapshot}"
  printf 'preserve published output\n' > "${directory}/sentinel"
  printf 'OLD_MANIFEST=1\nsecond=line\n' > "${directory}/manifest.env"
  printf 'extra\000published\n' > "${directory}/extra.bin"
  cp -a -- "${directory}/." "${snapshot}/"
  find -- "${directory}" -mindepth 1 -maxdepth 1 -printf '%f\0' \
    | LC_ALL=C sort -z -- > "${snapshot}.entries"
}

assert_no_transaction_directories() {
  local directory="$1"
  local output_parent
  local output_name
  local retained=""

  output_parent="$(dirname -- "${directory}")"
  output_name="$(basename -- "${directory}")"
  retained="$(
    find -- "${output_parent}" -mindepth 1 -maxdepth 1 -type d \
      \( -name ".${output_name}.staging.*" -o -name ".${output_name}.backup.*" \) \
      -print -quit
  )"
  [ -z "${retained}" ] || fail "transaction directory was retained: ${retained}"
}

assert_existing_output_preserved() {
  local directory="$1"
  local snapshot="$2"

  cmp -s -- "${snapshot}/sentinel" "${directory}/sentinel" || \
    fail "existing output sentinel changed byte-for-byte: ${directory}"
  cmp -s -- "${snapshot}/manifest.env" "${directory}/manifest.env" || \
    fail "existing manifest changed byte-for-byte: ${directory}"
  cmp -s -- "${snapshot}/extra.bin" "${directory}/extra.bin" || \
    fail "existing extra file changed byte-for-byte: ${directory}"
  find -- "${directory}" -mindepth 1 -maxdepth 1 -printf '%f\0' \
    | LC_ALL=C sort -z -- > "${snapshot}.actual-entries"
  cmp -s -- "${snapshot}.entries" "${snapshot}.actual-entries" || \
    fail "existing output top-level entry set changed: ${directory}"
  assert_no_transaction_directories "${directory}"
}

assert_probe_empty() {
  local probe_file="$1"
  local label="$2"

  [ ! -s "${probe_file}" ] || fail "${label} unexpectedly triggered probe ${probe_file}"
}

expect_builder_failure_preserving() {
  local label="$1"
  local expected_message="$2"
  local scenario_output="$3"
  shift 3
  local failure_log="${test_root}/${label}.log"
  local snapshot="${test_root}/snapshots/${label}"

  seed_existing_output "${scenario_output}" "${snapshot}"
  if "$@" > "${failure_log}" 2>&1; then
    fail "${label} unexpectedly succeeded"
  fi
  if ! grep -Fq -- "${expected_message}" "${failure_log}"; then
    cat "${failure_log}" >&2
    fail "${label} did not report: ${expected_message}"
  fi
  assert_existing_output_preserved "${scenario_output}" "${snapshot}"
}

assert_unsafe_segment_rejected() {
  local variable_name="$1"
  local unsafe_value="$2"
  local sequence="$3"
  local scenario_output="${test_root}/unsafe-${variable_name}-${sequence}"

  expect_builder_failure_preserving \
    "unsafe-${variable_name}-${sequence}" \
    "Unsafe ${variable_name}:" \
    "${scenario_output}" \
    run_builder_with_override "${variable_name}" "${unsafe_value}" "${scenario_output}"
}

unsafe_variables=(
  NODE_DEFAULT_ENV
  NVM_VERSION
  NODE_VERSION
  BUN_VERSION
  PNPM_VERSION
  OPENCODE_VERSION
  CODEX_VERSION
  CLAUDE_CODE_VERSION
  CLAUDE_CODE_ROUTER_VERSION
)
unsafe_values=(
  '../escape'
  'tools/child'
  'bad value'
  $'bad\nvalue'
)
sequence=0
for variable_name in "${unsafe_variables[@]}"; do
  for unsafe_value in "${unsafe_values[@]}"; do
    sequence=$((sequence + 1))
    assert_unsafe_segment_rejected "${variable_name}" "${unsafe_value}" "${sequence}"
  done
done
for unsafe_value in . ..; do
  sequence=$((sequence + 1))
  assert_unsafe_segment_rejected NODE_DEFAULT_ENV "${unsafe_value}" "${sequence}"
done

wrong_archive_sha256=0000000000000000000000000000000000000000000000000000000000000000
wrong_nvm_output="${test_root}/wrong-nvm-sha-output"
wrong_nvm_probe="${test_root}/wrong-nvm-sha-probe"
expect_builder_failure_preserving \
  wrong-nvm-sha256 \
  "NVM archive SHA256 mismatch: expected ${wrong_archive_sha256}, actual ${nvm_archive_sha256}" \
  "${wrong_nvm_output}" \
  run_builder_with_sha_probe NVM_ARCHIVE_SHA256 "${wrong_archive_sha256}" \
    "${wrong_nvm_output}" "${wrong_nvm_probe}"
assert_probe_empty "${wrong_nvm_probe}.archive" 'wrong NVM SHA archive ordering'
assert_probe_empty "${wrong_nvm_probe}.node" 'wrong NVM SHA Node execution ordering'
assert_probe_empty "${wrong_nvm_probe}.bun" 'wrong NVM SHA Bun execution ordering'
assert_probe_empty "${wrong_nvm_probe}.npm" 'wrong NVM SHA npm execution ordering'
wrong_node_output="${test_root}/wrong-node-sha-output"
wrong_node_probe="${test_root}/wrong-node-sha-probe"
expect_builder_failure_preserving \
  wrong-node-sha256 \
  "Node archive SHA256 mismatch: expected ${wrong_archive_sha256}, actual ${node_archive_sha256}" \
  "${wrong_node_output}" \
  run_builder_with_sha_probe NODE_ARCHIVE_SHA256 "${wrong_archive_sha256}" \
    "${wrong_node_output}" "${wrong_node_probe}"
assert_probe_empty "${wrong_node_probe}.archive" 'wrong Node SHA archive ordering'
assert_probe_empty "${wrong_node_probe}.node" 'wrong Node SHA Node execution ordering'
assert_probe_empty "${wrong_node_probe}.bun" 'wrong Node SHA Bun execution ordering'
assert_probe_empty "${wrong_node_probe}.npm" 'wrong Node SHA npm execution ordering'
wrong_bun_output="${test_root}/wrong-bun-sha-output"
wrong_bun_probe="${test_root}/wrong-bun-sha-probe"
expect_builder_failure_preserving \
  wrong-bun-sha256 \
  "Bun archive SHA256 mismatch: expected ${wrong_archive_sha256}, actual ${bun_archive_sha256}" \
  "${wrong_bun_output}" \
  run_builder_with_sha_probe BUN_ARCHIVE_SHA256 "${wrong_archive_sha256}" \
    "${wrong_bun_output}" "${wrong_bun_probe}"
assert_probe_empty "${wrong_bun_probe}.archive" 'wrong Bun SHA archive ordering'
assert_probe_empty "${wrong_bun_probe}.node" 'wrong Bun SHA Node execution ordering'
assert_probe_empty "${wrong_bun_probe}.bun" 'wrong Bun SHA Bun execution ordering'
assert_probe_empty "${wrong_bun_probe}.npm" 'wrong Bun SHA npm execution ordering'

for archive_variable in NVM_ARCHIVE_URL NODE_ARCHIVE_URL BUN_ARCHIVE_URL; do
  missing_output="${test_root}/missing-${archive_variable}"
  expect_builder_failure_preserving \
    "missing-${archive_variable}" \
    'fixture download failure:' \
    "${missing_output}" \
    run_builder_with_download_failure "${archive_variable}" "${missing_output}"
done

wrong_node_version_output="${test_root}/wrong-node-version-output"
expect_builder_failure_preserving \
  wrong-node-version \
  'Node version mismatch: expected v24.17.0, actual v24.17.1' \
  "${wrong_node_version_output}" \
  run_builder_with_fixture FIXTURE_NODE_REPORTED_VERSION v24.17.1 "${wrong_node_version_output}"
npm_failure_output="${test_root}/npm-failure-output"
expect_builder_failure_preserving \
  npm-failure \
  'fixture npm failure' \
  "${npm_failure_output}" \
  run_builder_with_fixture FIXTURE_NPM_FAIL 1 "${npm_failure_output}"
wrong_bun_version_output="${test_root}/wrong-bun-version-output"
expect_builder_failure_preserving \
  wrong-bun-version \
  'Bun version mismatch: expected 1.3.15, actual 1.3.14' \
  "${wrong_bun_version_output}" \
  run_builder_with_override BUN_VERSION 1.3.15 "${wrong_bun_version_output}"
wrong_bunx_output="${test_root}/wrong-bunx-version-output"
expect_builder_failure_preserving \
  wrong-bunx-version \
  'Bunx version mismatch: expected 1.3.14, actual 1.3.13' \
  "${wrong_bunx_output}" \
  run_builder_with_fixture FIXTURE_BAD_BUNX 1 "${wrong_bunx_output}"
symlink_output="${test_root}/symlink-output"
expect_builder_failure_preserving \
  symlink-bun-member \
  'Bun archive member bun-linux-x64/bun is not a regular file' \
  "${symlink_output}" \
  run_builder_with_symlink_archive "${symlink_output}"

publish_failure_output="${test_root}/publish-failure-output"
expect_builder_failure_preserving \
  publish-failure \
  'Could not publish staged Node runtime output' \
  "${publish_failure_output}" \
  run_builder_with_publish_failure "${publish_failure_output}"

staging_install_failure_output="${test_root}/staging-install-failure-output"
expect_builder_failure_preserving \
  staging-install-failure \
  'fixture staging install failure:' \
  "${staging_install_failure_output}" \
  run_builder_with_staging_install_failure "${staging_install_failure_output}"

success_snapshot="${test_root}/snapshots/success-old-output"
success_probe="${test_root}/success-probe"
seed_existing_output "${output_dir}" "${success_snapshot}"
run_builder_with_success_probes "${output_dir}" "${success_probe}"
assert_no_transaction_directories "${output_dir}"
[ ! -e "${output_dir}/sentinel" ] || fail 'successful publication retained the old sentinel'
grep -Fqx tar "${success_probe}.archive" || fail 'normal archive probe did not delegate tar'
grep -Fqx unzip "${success_probe}.archive" || fail 'normal archive probe did not delegate unzip'
grep -Fqx zipinfo "${success_probe}.archive" || fail 'normal archive probe did not delegate zipinfo'
[ -s "${success_probe}.node" ] || fail 'normal execution probe did not execute Node'
[ -s "${success_probe}.bun" ] || fail 'normal execution probe did not execute Bun/Bunx'
[ -s "${success_probe}.npm" ] || fail 'normal execution probe did not execute npm'

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
grep -Fqx 'bun@1.3.14' "${output_dir}/node-tools.packages" || fail 'node-tools.packages is missing bun@1.3.14'

grep -Fqx 'BUN_VERSION=1.3.14' "${output_dir}/manifest.env" || fail 'manifest is missing BUN_VERSION=1.3.14'
for key in NVM_SHA256 NODE_SHA256 BUN_SOURCE_SHA256 NODE_TOOLS_SHA256 PACKAGE_SET_SHA256; do
  grep -Eq "^${key}=[0-9a-f]{64}$" "${output_dir}/manifest.env" || fail "manifest is missing ${key}"
done
manifest_nvm_sha256="$(sed -n 's/^NVM_SHA256=//p' "${output_dir}/manifest.env")"
manifest_node_sha256="$(sed -n 's/^NODE_SHA256=//p' "${output_dir}/manifest.env")"
manifest_bun_source_sha256="$(sed -n 's/^BUN_SOURCE_SHA256=//p' "${output_dir}/manifest.env")"
[ "${manifest_nvm_sha256}" = "${nvm_archive_sha256}" ] || fail 'manifest NVM_SHA256 does not match the fixed NVM archive'
[ "${manifest_node_sha256}" = "${node_archive_sha256}" ] || fail 'manifest NODE_SHA256 does not match the fixed Node archive'
[ "${manifest_bun_source_sha256}" = "${bun_archive_sha256}" ] || fail 'manifest BUN_SOURCE_SHA256 does not match the fake Bun zip'

if find "${output_dir}" -maxdepth 1 -type f -name '*.zip' -print -quit | grep -q .; then
  fail 'output unexpectedly contains a standalone Bun zip'
fi

tools_extract="${test_root}/tools"
mkdir -p "${tools_extract}"
tar -Jxf "${output_dir}/node-tools.tar.xz" -C "${tools_extract}"
for command_name in pnpm opencode codex claude ccr; do
  [ -x "${tools_extract}/bin/${command_name}" ] || fail "tools archive is missing ${command_name}"
done
[ -x "${tools_extract}/bin/bun" ] || fail 'tools archive is missing executable bin/bun'
[ -L "${tools_extract}/bin/bunx" ] || fail 'tools archive is missing bin/bunx symlink'
[ "$(readlink "${tools_extract}/bin/bunx")" = 'bun' ] || fail 'bin/bunx is not a relative symlink to bun'
[ "$("${tools_extract}/bin/bun" --version)" = '1.3.14' ] || fail 'bin/bun version does not match 1.3.14'
[ "$("${tools_extract}/bin/bunx" --version)" = '1.3.14' ] || fail 'bin/bunx version does not match 1.3.14'

grep -Fq 'cp -f -- "${source}" "${destination}"' "${builder}" || \
  fail 'download_source does not protect local source operands'
grep -Fq 'curl -fL --retry 3 -o "${destination}" -- "${source}"' "${builder}" || \
  fail 'download_source does not protect remote source operands'
for required_command in \
  'sha256sum -- "${file}"' \
  'mktemp -d -- "${output_parent}/.${output_name}.staging.XXXXXX"' \
  'install -d -m 0755 -- "${staged_output}" "${work_dir}"' \
  'mkdir -p -- "${node_root}" "${tools_root}" "${npm_cache}" "${bun_root}"' \
  'ln -s -- bun "${tools_root}/bin/bunx"' \
  'readlink -- "${root}/bin/bunx"' \
  'unzip -Z1 -- "${bun_archive}"' \
  'zipinfo -l -- "${bun_archive}"' \
  'unzip -p -- "${bun_archive}" "${bun_member}"' \
  'find -- "${staged_output}"' \
  'LC_ALL=C sort --'; do
  grep -Fq -- "${required_command}" "${builder}" || \
    fail "builder is missing option terminator contract: ${required_command}"
done

printf 'PASS: offline Node runtime builder\n'
