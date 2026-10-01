# Omarchy N1X bring-up

This branch publishes the experimental September 2026 N1X implementation. The three matching branches are:

- [Kernel and package recipes](https://github.com/spencerbull/omarchy-pkgs/tree/n1x-bringup)
- [Omarchy installer](https://github.com/spencerbull/omarchy/tree/n1x-bringup)
- [AArch64 ISO builder](https://github.com/spencerbull/omarchy-iso/tree/n1x-bringup)

Each fork also has an `n1x-base` branch at the last commit before its N1X snapshot. The pull request from `n1x-bringup` to `n1x-base` shows the N1X changes on top of the earlier GB10/AArch64 foundation; it is not a proposal to merge into upstream or the fork's default branch.

## Recorded hardware status

On September 3, the Dell XPS 16 DX16263 booted the installed system with the panel console and LUKS prompt visible. Kernel `7.0.14-2-n1x` restored the internal keyboard and touchpad after the MediaTek I2C ACPI and GPIO debounce patches. A software-rendered Hyprland desktop ran on SimpleDRM with the NVIDIA stack disabled.

NVIDIA 610.57.04 bound GPU `10de:2e06` but failed to initialize GSP. GPU acceleration, the FF-A embedded-controller interface (battery/lid/thermal/UCSI), invisible hyprlock under software rendering, and automatic rescue-UKI refresh after kernel upgrades remain open in this snapshot. Hardware results are historical; this publication does not claim a new kernel/ISO build or physical retest. The historical `TODO.md` and `N1X_HANDOFF.md` contain earlier entries superseded by their later dated results.

## ISO changes

[`bin/omarchy-iso-make`](bin/omarchy-iso-make) adds explicit `--n1x` selection and checks the local AArch64 package bundle. The builder uses the N1X kernel, ARM64 GRUB, a non-Plymouth live initramfs, and N1X recovery/probe support, including SSH file permissions and generated boot-entry checks.

Clone the companion installer branch beside this checkout. Prepare a package bundle containing exactly one matching `linux-n1x` / `linux-n1x-headers` pair, the additional AArch64 packages required by the builder, and a `SHA256SUMS` manifest covering every archive. See the existing repository build documentation for the Docker/Archiso environment; the kernel pair alone is not a complete offline package bundle.

Initialize the pinned Archiso submodule, then build from this repository root:

```bash
git submodule update --init archiso
OMARCHY_PATH=/absolute/path/to/omarchy \
  OMARCHY_INSTALLER_REF=n1x-bringup \
  bin/omarchy-iso-make --n1x --package-dir /absolute/path/to/package-bundle \
  --local-source --no-boot-offer
```

Focused checks:

```bash
bash test/gb10-build-mode-test.sh
OMARCHY_SOURCE_UNDER_TEST=/absolute/path/to/omarchy \
  bash test/gb10-node-handoff-test.sh
```

[`N1X_HANDOFF.md`](N1X_HANDOFF.md) retains detailed build records and diagnosis. Its later recovery5 and pkgrel 2 entries supersede the earlier incomplete checklists. Recorded recovery5 SHA-256: `d68bd5243418d4d69e3346b970cca742626b61ab8fdeb4ba1e1356d23ea91735`. Compiled packages and ISO images are not published by these source PRs.
