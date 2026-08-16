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
  BUN_VERSION
  PNPM_VERSION
  OPENCODE_VERSION
  CODEX_VERSION
  NVM_ARCHIVE_URL
  NODE_ARCHIVE_URL
  BUN_ARCHIVE_URL
  NVM_ARCHIVE_SHA256
  NODE_ARCHIVE_SHA256
  BUN_ARCHIVE_SHA256
)
for variable_name in "${required_variables[@]}"; do
  if [ -z "${!variable_name:-}" ]; then
    printf '%s is required\n' "${variable_name}" >&2
    exit 2
  fi
done

require_safe_segment() {
  local variable_name="$1"
  local value="${!variable_name:-}"
  local pattern="$2"

  if [ -z "${value}" ] || [ "${value}" = . ] || [ "${value}" = .. ] || \
    [[ ! "${value}" =~ ${pattern} ]]; then
    printf 'Unsafe %s: %q\n' "${variable_name}" "${value}" >&2
    exit 1
  fi
}

require_sha256() {
  local variable_name="$1"
  local value="${!variable_name:-}"

  if [[ ! "${value}" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'Invalid %s: %q\n' "${variable_name}" "${value}" >&2
    exit 1
  fi
}

require_safe_segment NODE_DEFAULT_ENV '^[A-Za-z0-9][A-Za-z0-9._-]*$'
for variable_name in \
  NVM_VERSION NODE_VERSION BUN_VERSION PNPM_VERSION OPENCODE_VERSION \
  CODEX_VERSION; do
  require_safe_segment "${variable_name}" '^[A-Za-z0-9][A-Za-z0-9._+-]*$'
done
for variable_name in NVM_ARCHIVE_SHA256 NODE_ARCHIVE_SHA256 BUN_ARCHIVE_SHA256; do
  require_sha256 "${variable_name}"
done

download_source() {
  local source="$1"
  local destination="$2"

  if [ -f "${source}" ]; then
    cp -f -- "${source}" "${destination}"
  else
    curl -fL --retry 3 -o "${destination}" -- "${source}"
  fi
}

verify_fixed_sha256() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local actual=""

  actual="$(sha256sum -- "${file}" | awk '{print $1}')"
  if [ "${actual}" != "${expected}" ]; then
    printf '%s SHA256 mismatch: expected %s, actual %s\n' \
      "${label}" "${expected}" "${actual}" >&2
    return 1
  fi
  printf '%s\n' "${actual}"
}

output_parent="$(dirname -- "${output_dir}")"
output_name="$(basename -- "${output_dir}")"
mkdir -p -- "${output_parent}"

staging_parent=""
if ! staging_parent="$(mktemp -d -- "${output_parent}/.${output_name}.staging.XXXXXX")"; then
  printf 'Could not create Node runtime staging directory\n' >&2
  exit 1
fi
cleanup() {
  if [ -n "${staging_parent}" ] && \
    { [ -e "${staging_parent}" ] || [ -L "${staging_parent}" ]; }; then
    if ! rm -rf -- "${staging_parent}"; then
      printf 'Retained Node runtime staging directory for recovery: %s\n' \
        "${staging_parent}" >&2
    fi
  fi
}
trap cleanup EXIT

staged_output="${staging_parent}/output"
work_dir="${staging_parent}/work"
install -d -m 0755 -- "${staged_output}" "${work_dir}"

nvm_archive="${staged_output}/nvm-v${NVM_VERSION}.tar.gz"
node_archive="${staged_output}/node-v${NODE_VERSION}-linux-x64.tar.xz"
bun_archive="${work_dir}/bun-linux-x64.zip"
tools_archive="${staged_output}/node-tools.tar.xz"
packages_file="${staged_output}/node-tools.packages"
manifest_file="${staged_output}/manifest.env"

download_source "${NVM_ARCHIVE_URL}" "${nvm_archive}"
download_source "${NODE_ARCHIVE_URL}" "${node_archive}"
download_source "${BUN_ARCHIVE_URL}" "${bun_archive}"

nvm_source_sha256=""
node_source_sha256=""
bun_source_sha256=""
if ! nvm_source_sha256="$(
  verify_fixed_sha256 'NVM archive' "${nvm_archive}" "${NVM_ARCHIVE_SHA256}"
)"; then
  exit 1
fi
if ! node_source_sha256="$(
  verify_fixed_sha256 'Node archive' "${node_archive}" "${NODE_ARCHIVE_SHA256}"
)"; then
  exit 1
fi
if ! bun_source_sha256="$(
  verify_fixed_sha256 'Bun archive' "${bun_archive}" "${BUN_ARCHIVE_SHA256}"
)"; then
  exit 1
fi

if ! tar -tzf "${nvm_archive}" > /dev/null; then
  printf 'Unable to inspect NVM archive\n' >&2
  exit 1
fi
if ! tar -tJf "${node_archive}" > /dev/null; then
  printf 'Unable to inspect Node archive\n' >&2
  exit 1
fi

bun_member="bun-linux-x64/bun"
if ! bun_archive_members="$(unzip -Z1 -- "${bun_archive}")"; then
  printf 'Unable to list Bun archive members\n' >&2
  exit 1
fi
bun_member_count="$(
  printf '%s\n' "${bun_archive_members}" \
    | awk -v member="${bun_member}" '$0 == member { count++ } END { print count + 0 }'
)"
if [ "${bun_member_count}" -ne 1 ]; then
  printf 'Bun archive member count mismatch for %s: expected 1, actual %s\n' \
    "${bun_member}" "${bun_member_count}" >&2
  exit 1
fi
if ! bun_archive_listing="$(zipinfo -l -- "${bun_archive}")"; then
  printf 'Unable to inspect Bun archive members\n' >&2
  exit 1
fi
bun_member_mode="$(
  printf '%s\n' "${bun_archive_listing}" \
    | awk -v member="${bun_member}" '$NF == member { print $1 }'
)"
if [ -z "${bun_member_mode}" ] || [ "${bun_member_mode:0:1}" != '-' ]; then
  printf 'Bun archive member %s is not a regular file: mode %s\n' \
    "${bun_member}" "${bun_member_mode:-unknown}" >&2
  exit 1
fi

node_root="${work_dir}/node"
tools_root="${work_dir}/environments/${NODE_DEFAULT_ENV}"
npm_cache="${work_dir}/npm-cache"
bun_root="${work_dir}/bun"
mkdir -p -- "${node_root}" "${tools_root}" "${npm_cache}" "${bun_root}"
tar -Jxf "${node_archive}" --strip-components=1 -C "${node_root}"
bun_binary="${bun_root}/bun"
install -m 0600 -- /dev/null "${bun_binary}"
if ! unzip -p -- "${bun_archive}" "${bun_member}" > "${bun_binary}"; then
  printf 'Unable to extract Bun archive member %s\n' "${bun_member}" >&2
  exit 1
fi
chmod 0755 -- "${bun_binary}"

node_actual_version=""
if ! node_actual_version="$("${node_root}/bin/node" --version 2>&1)"; then
  printf 'Node version check failed: expected v%s, actual %s\n' \
    "${NODE_VERSION}" "${node_actual_version:-<execution failed>}" >&2
  exit 1
fi
if [ "${node_actual_version}" != "v${NODE_VERSION}" ]; then
  printf 'Node version mismatch: expected v%s, actual %s\n' \
    "${NODE_VERSION}" "${node_actual_version}" >&2
  exit 1
fi
if [ ! -x "${node_root}/bin/npm" ]; then
  printf 'Downloaded Node archive does not contain npm\n' >&2
  exit 1
fi
bun_actual_version=""
if bun_actual_version="$("${bun_binary}" --version 2>&1)"; then
  :
else
  bun_version_status=$?
  printf 'Bun version check failed: expected %s, actual %s (exit status %s)\n' \
    "${BUN_VERSION}" "${bun_actual_version:-<no output>}" "${bun_version_status}" >&2
  exit 1
fi
if [ "${bun_actual_version}" != "${BUN_VERSION}" ]; then
  printf 'Bun version mismatch: expected %s, actual %s\n' \
    "${BUN_VERSION}" "${bun_actual_version}" >&2
  exit 1
fi

tool_packages=(
  "pnpm@${PNPM_VERSION}"
  "opencode-ai@${OPENCODE_VERSION}"
  "@openai/codex@${CODEX_VERSION}"
)
printf '%s\n' "${tool_packages[@]}" > "${packages_file}"
printf 'bun@%s\n' "${BUN_VERSION}" >> "${packages_file}"

if ! PATH="${node_root}/bin:${PATH}" \
  NPM_CONFIG_CACHE="${npm_cache}" \
    "${node_root}/bin/npm" install \
      --global \
      --prefix "${tools_root}" \
      --no-audit \
      --no-fund \
      "${tool_packages[@]}"; then
  printf 'npm package installation failed\n' >&2
  exit 1
fi

install -d -m 0755 -- "${tools_root}/bin"
install -m 0755 -- "${bun_binary}" "${tools_root}/bin/bun"
ln -s -- bun "${tools_root}/bin/bunx"

validate_tools_environment() {
  local root="$1"
  local command_name=""
  local actual_version=""
  local bunx_target=""

  for command_name in pnpm opencode codex bun bunx; do
    if [ ! -x "${root}/bin/${command_name}" ]; then
      printf 'Installed Node tools are missing executable bin/%s\n' \
        "${command_name}" >&2
      return 1
    fi
  done

  actual_version=""
  if ! actual_version="$("${root}/bin/bun" --version 2>&1)"; then
    printf 'Bun version check failed: expected %s, actual %s\n' \
      "${BUN_VERSION}" "${actual_version:-<execution failed>}" >&2
    return 1
  fi
  if [ "${actual_version}" != "${BUN_VERSION}" ]; then
    printf 'Bun version mismatch: expected %s, actual %s\n' \
      "${BUN_VERSION}" "${actual_version}" >&2
    return 1
  fi

  actual_version=""
  if ! actual_version="$("${root}/bin/bunx" --version 2>&1)"; then
    printf 'Bunx version check failed: expected %s, actual %s\n' \
      "${BUN_VERSION}" "${actual_version:-<execution failed>}" >&2
    return 1
  fi
  if [ "${actual_version}" != "${BUN_VERSION}" ]; then
    printf 'Bunx version mismatch: expected %s, actual %s\n' \
      "${BUN_VERSION}" "${actual_version}" >&2
    return 1
  fi
  if [ ! -L "${root}/bin/bunx" ]; then
    printf 'Installed Node tools bin/bunx is not a symlink\n' >&2
    return 1
  fi
  bunx_target="$(readlink -- "${root}/bin/bunx")"
  if [ "${bunx_target}" != bun ]; then
    printf 'Installed Node tools bin/bunx target mismatch: expected bun, actual %s\n' \
      "${bunx_target}" >&2
    return 1
  fi
}

validate_tools_environment "${tools_root}"

tar -cJf "${tools_archive}" -C "${tools_root}" .

validated_tools_root="${work_dir}/validated-tools"
mkdir -p -- "${validated_tools_root}"
if ! tar -Jxf "${tools_archive}" -C "${validated_tools_root}"; then
  printf 'Unable to validate staged Node tools archive\n' >&2
  exit 1
fi
validate_tools_environment "${validated_tools_root}"

{
  printf 'NODE_VERSION=%s\n' "${NODE_VERSION}"
  printf 'NVM_VERSION=%s\n' "${NVM_VERSION}"
  printf 'NODE_DEFAULT_ENV=%s\n' "${NODE_DEFAULT_ENV}"
  printf 'BUN_VERSION=%s\n' "${BUN_VERSION}"
  printf 'NVM_SHA256=%s\n' "${nvm_source_sha256}"
  printf 'NODE_SHA256=%s\n' "${node_source_sha256}"
  printf 'BUN_SOURCE_SHA256=%s\n' "${bun_source_sha256}"
  printf 'NODE_TOOLS_SHA256=%s\n' "$(sha256sum -- "${tools_archive}" | awk '{print $1}')"
  printf 'PACKAGE_SET_SHA256=%s\n' "$(sha256sum -- "${packages_file}" | awk '{print $1}')"
  printf 'GENERATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${manifest_file}"

manifest_value() {
  local key="$1"
  sed -n "s/^${key}=//p" -- "${manifest_file}" | head -n 1
}

verify_manifest_value() {
  local key="$1"
  local expected="$2"
  local actual=""

  actual="$(manifest_value "${key}")"
  if [ "${actual}" != "${expected}" ]; then
    printf 'Manifest value mismatch for %s: expected %s, actual %s\n' \
      "${key}" "${expected}" "${actual:-<missing>}" >&2
    return 1
  fi
}

verify_manifest_value NODE_VERSION "${NODE_VERSION}"
verify_manifest_value NVM_VERSION "${NVM_VERSION}"
verify_manifest_value NODE_DEFAULT_ENV "${NODE_DEFAULT_ENV}"
verify_manifest_value BUN_VERSION "${BUN_VERSION}"
verify_manifest_value NVM_SHA256 "${nvm_source_sha256}"
verify_manifest_value NODE_SHA256 "${node_source_sha256}"
verify_manifest_value BUN_SOURCE_SHA256 "${bun_source_sha256}"
verify_manifest_value NODE_TOOLS_SHA256 \
  "$(sha256sum -- "${tools_archive}" | awk '{print $1}')"
verify_manifest_value PACKAGE_SET_SHA256 \
  "$(sha256sum -- "${packages_file}" | awk '{print $1}')"

expected_output_entries=$'manifest.env\nnode-tools.packages\nnode-tools.tar.xz\nnode-v'"${NODE_VERSION}"$'-linux-x64.tar.xz\nnvm-v'"${NVM_VERSION}"'.tar.gz'
actual_output_entries="$(
  find -- "${staged_output}" -mindepth 1 -maxdepth 1 -printf '%f\n' \
    | LC_ALL=C sort --
)"
if [ "${actual_output_entries}" != "${expected_output_entries}" ]; then
  printf 'Staged Node runtime output has unexpected entries: %s\n' \
    "${actual_output_entries}" >&2
  exit 1
fi

backup_parent=""
backup_output=""
if [ -e "${output_dir}" ] || [ -L "${output_dir}" ]; then
  if ! backup_parent="$(mktemp -d -- "${output_parent}/.${output_name}.backup.XXXXXX")"; then
    printf 'Could not create Node runtime backup directory\n' >&2
    exit 1
  fi
  backup_output="${backup_parent}/output"
  if ! mv -T -- "${output_dir}" "${backup_output}"; then
    printf 'Could not back up existing Node runtime output\n' >&2
    if ! rmdir -- "${backup_parent}"; then
      printf 'Retained empty Node runtime backup directory: %s\n' \
        "${backup_parent}" >&2
    fi
    exit 1
  fi
fi

if ! mv -T -- "${staged_output}" "${output_dir}"; then
  printf 'Could not publish staged Node runtime output\n' >&2
  if [ -n "${backup_output}" ]; then
    if [ ! -e "${output_dir}" ] && [ ! -L "${output_dir}" ]; then
      if mv -T -- "${backup_output}" "${output_dir}"; then
        backup_output=""
        if ! rmdir -- "${backup_parent}"; then
          printf 'Retained empty Node runtime backup directory: %s\n' \
            "${backup_parent}" >&2
        else
          backup_parent=""
        fi
      else
        printf 'Could not restore previous Node runtime output; retained backup: %s\n' \
          "${backup_output}" >&2
      fi
    else
      printf 'Node runtime output path is occupied; retained backup: %s\n' \
        "${backup_output}" >&2
    fi
  fi
  exit 1
fi

if [ -n "${backup_parent}" ]; then
  if ! rm -rf -- "${backup_parent}"; then
    printf 'Published Node runtime output; retained previous backup: %s\n' \
      "${backup_parent}" >&2
  fi
  backup_parent=""
  backup_output=""
fi
if ! rm -rf -- "${staging_parent}"; then
  printf 'Published Node runtime output; retained staging directory: %s\n' \
    "${staging_parent}" >&2
else
  staging_parent=""
fi
trap - EXIT

printf 'Created offline Node %s environment %s at %s\n' \
  "${NODE_VERSION}" "${NODE_DEFAULT_ENV}" "${output_dir}"
