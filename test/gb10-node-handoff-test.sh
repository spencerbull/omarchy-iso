#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
omarchy_source=${OMARCHY_SOURCE_UNDER_TEST:?Set OMARCHY_SOURCE_UNDER_TEST to the Omarchy GB10 branch worktree}
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

source "$omarchy_source/install/helpers/node-release.sh"
source "$repo_root/builder/gb10-omarchy-source.sh"

touch "$fixture/node-v24.7.0-linux-arm64.tar.gz"
node_platform=$(omarchy-node-release-platform aarch64)
node_archive=$(omarchy-find-node-release "$fixture" "$node_platform")
node_version=$(omarchy-node-release-version "$node_archive" "$node_platform")

[[ $node_platform == linux-arm64 ]]
[[ $node_archive == "$fixture/node-v24.7.0-linux-arm64.tar.gz" ]]
[[ $node_version == 24.7.0 ]]
grep -Fq 'install/helpers/node-release.sh' "$repo_root/builder/gb10-omarchy-source.sh"
grep -Fq 'cannot consume the bundled AArch64 Node.js release' "$repo_root/builder/gb10-omarchy-source.sh"

validate_arm_omarchy_source "$omarchy_source"

fixture_source="$fixture/omarchy-source"
cp -as "$omarchy_source" "$fixture_source"

mv "$fixture_source/install/helpers/logging.sh" "$fixture/logging.sh"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "GB10 source validation accepted a missing strict logging helper" >&2
  exit 1
fi
mv "$fixture/logging.sh" "$fixture_source/install/helpers/logging.sh"

cp --remove-destination "$omarchy_source/install/helpers/errors.sh" "$fixture_source/install/helpers/errors.sh"
sed -i '/trap exit_handler EXIT/d' "$fixture_source/install/helpers/errors.sh"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "GB10 source validation accepted missing EXIT cleanup" >&2
  exit 1
fi
cp --remove-destination "$omarchy_source/install/helpers/errors.sh" "$fixture_source/install/helpers/errors.sh"

cp --remove-destination "$omarchy_source/bin/omarchy-update-system-pkgs" "$fixture_source/bin/omarchy-update-system-pkgs"
sed -i '/omarchy-guard-gb10-lifecycle/d' "$fixture_source/bin/omarchy-update-system-pkgs"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "GB10 source validation accepted an unguarded public update stage" >&2
  exit 1
fi
cp --remove-destination "$omarchy_source/bin/omarchy-update-system-pkgs" "$fixture_source/bin/omarchy-update-system-pkgs"

cp --remove-destination "$omarchy_source/install/config/hardware/nvidia/gb10-kernel.sh" "$fixture_source/install/config/hardware/nvidia/gb10-kernel.sh"

cp --remove-destination "$omarchy_source/install/config/hardware/nvidia/n1x-kernel.sh" "$fixture_source/install/config/hardware/nvidia/n1x-kernel.sh"
sed -i '/authorization disappeared before the N1x kernel transition/,/^[[:space:]]*fi[[:space:]]*$/{/^[[:space:]]*return 1[[:space:]]*$/d;}' "$fixture_source/install/config/hardware/nvidia/n1x-kernel.sh"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "ARM source validation accepted an authorization-loss N1x kernel guard without an explicit failure" >&2
  exit 1
fi
cp --remove-destination "$omarchy_source/install/config/hardware/nvidia/n1x-kernel.sh" "$fixture_source/install/config/hardware/nvidia/n1x-kernel.sh"
sed -i '/authorization disappeared before the kernel transition/,/^[[:space:]]*fi[[:space:]]*$/{/^[[:space:]]*return 1[[:space:]]*$/d;}' "$fixture_source/install/config/hardware/nvidia/gb10-kernel.sh"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "GB10 source validation accepted an authorization-loss kernel guard without an explicit failure" >&2
  exit 1
fi
cp --remove-destination "$omarchy_source/install/config/hardware/nvidia/gb10-kernel.sh" "$fixture_source/install/config/hardware/nvidia/gb10-kernel.sh"

cp --remove-destination "$omarchy_source/install/login/limine-snapper.sh" "$fixture_source/install/login/limine-snapper.sh"
sed -i '1,/^fi$/d' "$fixture_source/install/login/limine-snapper.sh"
if validate_arm_omarchy_source "$fixture_source" >/dev/null 2>&1; then
  echo "GB10 source validation accepted only the late Limine authorization check" >&2
  exit 1
fi

echo "GB10 ISO-to-installer Node.js handoff tests passed"
