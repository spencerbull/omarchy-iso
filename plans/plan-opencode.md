# Custom Kernel Build for XPS / Panther Lake

## Background

Dell XPS 2026 (and similar Panther Lake systems) causes a kernel panic on Linux 7.0 when
SOF audio modules conflict with HDA drivers. The proper fix requires 13 kernel config
options that are missing from the stock Arch kernel. The AUR `linux-mainline` package
(currently at `v7.0-rc4`) is at the right release — we just need to inject the required
config options during build.

The `xps-14` branch has ~80% of the infrastructure (custom kernel flags, build script,
ISO integration, configurator changes). This plan adapts that work to use the AUR
`linux-mainline` PKGBUILD instead of building from `torvalds/linux` with a hand-rolled
PKGBUILD, and applies the config overrides via fragment files.

Reference: `issue.md` (Panther Lake audio notes and required kernel config options)

## Design Decisions

- **Package name:** `linux-mainline` (matches AUR, not `linux-custom` as on xps-14)
- **Config overrides:** Fragment files in `configs/kernel/` — `build-kernel` applies all
  `*.config` files found there via `scripts/config`. Scalable: new hardware = new file.
- **Blacklist:** Removed from repo. The custom kernel has the proper config options. For
  non-custom-kernel installs, `omarchy/install/config/hardware/fix-dell-xps-audio.sh`
  handles runtime detection and blacklisting.
- **Opt-in:** All custom kernel functionality is behind flags. Default builds are unchanged.

## Changes

### 1. `bin/omarchy-iso-build-kernel` — New file

Rewrite of the xps-14 branch version. Instead of generating an inline PKGBUILD that
clones `torvalds/linux`, this script:

1. Clones the AUR `linux-mainline` package repo
2. Reads all `configs/kernel/*.config` fragment files
3. Patches the PKGBUILD's `prepare()` to inject `scripts/config` calls after
   `cp ../config .config` but before `make olddefconfig`
4. Runs `makepkg` inside a Docker container to produce proper Arch packages
5. Outputs `linux-mainline-*.pkg.tar.zst` to `release/kernels/`

This gives us Arch's full PKGBUILD with proper `depends`, mkinitcpio integration, and
headers/docs sub-packages.

### 2. `configs/kernel/panther-lake-audio.config` — New file

Config fragment containing the 13 kernel options from `issue.md`:

```
# Panther Lake audio — required for Dell XPS 2026 and similar systems
# These options fix the SOF/HDA driver conflict that causes kernel panic on boot.

CONFIG_SND_SOC_ACPI_AMD_SDCA_QUIRKS=m
CONFIG_SND_SOC_INTEL_SOF_TI_COMMON=m
CONFIG_SND_SOC_SDCA_FDL=y
CONFIG_SND_SOC_SDCA_CLASS=m
CONFIG_SND_SOC_SDCA_CLASS_FUNCTION=m
CONFIG_SND_SOC_SOF_INTEL_NVL=m
CONFIG_SND_SOC_SOF_NOVALAKE=m
CONFIG_SND_SOC_NAU8325=m
# CONFIG_SND_HDA_SCODEC_CS35L56_CAL_DEBUGFS is not set
# CONFIG_SND_SOC_CS35L56_CAL_DEBUGFS is not set
# CONFIG_SND_SOC_CS35L56_CAL_SET_CTRL is not set
# CONFIG_SND_SOC_CS530X_SPI is not set
# CONFIG_SND_SOC_RT5575 is not set
```

The `build-kernel` script parses this format and translates each line into the
appropriate `scripts/config --enable`, `--module`, `--set-val`, or `--disable` call.

### 3. `bin/omarchy-iso-make` — Edit (add flags)

Add three new CLI flags (adapted from xps-14 branch, renamed for `linux-mainline`):

| Flag | Effect |
|------|--------|
| `--build-kernel` | Builds `linux-mainline` from AUR + config fragments if not cached, then builds ISO. Sets `USE_CUSTOM_KERNEL=1`. |
| `--custom-kernel` | Expects pre-built kernel pkg in `release/kernels/`. Sets `USE_CUSTOM_KERNEL=1`. Errors if not found. |
| `--no-t2` | Drops `linux-t2` from the ISO package list. Sets `OMARCHY_NO_T2=1`. |

Also add:
- `LINUX_KERNEL_BRANCH` env var (default from `.envrc` or `v7.0-rc4`)
- Docker volume mount for `release/kernels/` when custom kernel is used
- Docker env vars: `USE_CUSTOM_KERNEL`, `LINUX_KERNEL_BRANCH`, `OMARCHY_NO_T2`
- ISO naming: append `-linux-mainline-{branch}` when custom kernel is used
- Mount `configs/kernel/` into the container for the build-kernel script

### 4. `builder/build-iso.sh` — Edit (custom kernel integration)

When `USE_CUSTOM_KERNEL=1` is set (adapted from xps-14 branch):

1. Copy kernel pkg from `/custom-kernel/` into pacman cache and offline mirror
2. Replace `linux-t2` with `linux-mainline` in `arch_packages` array
3. Patch bootloader configs via sed:
   - `vmlinuz-linux-t2` -> `vmlinuz-linux-mainline`
   - `initramfs-linux-t2.img` -> `initramfs-linux-mainline.img`
   - Targets: `grub.cfg`, `loopback.cfg`, efiboot entry, syslinux configs
4. Patch mkinitcpio preset (`linux.preset`)
5. Write `/root/omarchy_kernel` marker file containing `linux-mainline`
6. Swap `linux` for `linux-mainline` in a working copy of `archinstall.packages`
7. Filter `linux-mainline` out of the download list (it's already local)

When `OMARCHY_NO_T2=1` without custom kernel: just drop `linux-t2` from package list.

### 5. `configs/airootfs/root/configurator` — Edit (kernel detection)

Adapt the xps-14 branch changes:

- Before the T2 detection check, look for `/root/omarchy_kernel` marker
- If present, use its contents as `kernel_choice`
- Add the offline repo to `custom_repositories` in the archinstall JSON so archinstall
  can find the custom kernel package
- Otherwise fall back to existing T2/standard detection logic

### 6. `configs/airootfs/etc/modprobe.d/blacklist-panther-lake-audio.conf` — Delete

Remove the blacklist file from the repo. The custom kernel has the proper config options
built in. For installs using the stock kernel (without `--build-kernel`/`--custom-kernel`),
the omarchy installer's `fix-dell-xps-audio.sh` handles runtime detection and blacklisting
on Panther Lake hardware.

## Supporting Changes

- `.envrc.template` — New file documenting all env vars (adapted from xps-14)
- `.gitignore` — Add `.envrc`
- `README.md` — Document the new `--build-kernel`, `--custom-kernel`, `--no-t2` flags

## What Stays Unchanged

- `.github/workflows/nightly-build.yml` — no custom kernel in CI (too slow)
- `bin/omarchy-iso-boot` — unchanged
- `bin/omarchy-iso-release` — unchanged (custom kernel is opt-in)
- `configs/grub/`, `configs/efiboot/`, `configs/syslinux/` — patched at build time by
  `build-iso.sh`, not modified in the repo
- `omarchy/install/config/hardware/fix-dell-xps-audio.sh` — stays as runtime fallback
- `omarchy/install/config/hardware/fix-intel-panther-lake-display.sh` — stays as-is
