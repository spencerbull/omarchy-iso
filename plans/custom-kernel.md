# Custom Kernel Build for XPS / Panther Lake

## Context

Dell XPS 2026 (and similar Intel Panther Lake systems) causes a kernel panic on Linux 7.0 when SOF audio modules conflict with HDA drivers. The upstream Arch `linux` package config is missing several new Kconfig symbols introduced in 7.0, causing them to silently default to disabled.

A temporary blacklist workaround exists in the ISO (`configs/airootfs/etc/modprobe.d/blacklist-panther-lake-audio.conf`) that prevents the panic by disabling SOF/SoundWire modules. This kills audio but allows boot.

The proper fix is a custom `linux-mainline` kernel built with the correct config options. This plan adds that capability to the ISO build system.

## Core Approach

Build a custom `linux-mainline` kernel from the AUR PKGBUILD with platform-specific config fragments applied. Include the resulting package in the ISO's offline mirror. At install time, detect Panther Lake hardware and install the custom kernel instead of stock `linux`.

- **ISO boot kernel is unchanged** — the ISO continues to boot with `linux-t2`. The blacklist stays as a safety net for the live environment.
- **Custom kernel is for the installed system only** — it goes into the offline mirror and is selected by the configurator at install time.
- **Default builds auto-include the cached kernel** — if a pre-built kernel exists in `release/kernels/`, it is included in the ISO without any flags. Use `--no-custom-kernel` to skip it.

## Scalability

Platform-specific kernel config is organized as fragment files in `configs/kernel/`:

```
configs/kernel/
  xps-pantherlake.config    # Panther Lake audio fix
  future-platform.config    # Add more as needed
```

All `*.config` fragments are automatically discovered and merged into a single kernel build. The hardware detection in the configurator is similarly extensible — add a new detection block for each platform that needs the custom kernel.

To add support for a new platform:
1. Add `configs/kernel/<platform>.config` with the required Kconfig options.
2. Add a hardware detection block in the configurator's kernel selection logic.

## Required Kernel Config Options (Panther Lake Audio)

```
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

## Non-Goals

- No changes to the ISO's boot kernel or bootloader configs.
- No removal of the Panther Lake audio blacklist (kept as live-boot safety net).
- No changes to default ISO builds when no cached kernel exists.
- No changes to T2 Mac detection or `linux-t2` handling.

---

## File Changes

### 1. `bin/omarchy-iso-build-kernel` (new)

Standalone script that builds a custom `linux-mainline` kernel package.

Behavior:
- Clones the AUR `linux-mainline` PKGBUILD inside a Docker container.
- Reads all `configs/kernel/*.config` fragment files.
- Translates each config line into a `scripts/config` call (--enable, --module, --disable, --set-str, --set-val).
- Injects the config commands into the PKGBUILD's `prepare()` function before `make olddefconfig`, so Kconfig dependency resolution picks them up.
- Strips htmldocs from the build to save time and avoid texlive dependencies.
- Runs `makepkg` and copies resulting packages to `release/kernels/`.
- Controlled by `LINUX_KERNEL_BRANCH` env var (default: `v7.0-rc4`).

Usage:
```bash
# Build kernel (30-90min depending on hardware)
./bin/omarchy-iso-build-kernel

# Build with a specific kernel tag
LINUX_KERNEL_BRANCH=v7.0 ./bin/omarchy-iso-build-kernel
```

### 2. `configs/kernel/xps-pantherlake.config` (new)

Kernel config fragment with the 13 required options for Panther Lake audio. Uses standard Kconfig fragment syntax:
- `CONFIG_FOO=y` — built-in
- `CONFIG_FOO=m` — module
- `# CONFIG_FOO is not set` — disabled

### 3. `bin/omarchy-iso-make` (modify)

Add two new CLI flags:

| Flag | Effect |
|------|--------|
| `--build-kernel` | Build the kernel from source first, then build the ISO with it included |
| `--no-custom-kernel` | Skip including the custom kernel even if a cached package exists |

Default behavior (no flags): if `release/kernels/linux-mainline-*.pkg.tar.zst` exists, include it in the ISO. If it doesn't exist, build the ISO without it (standard build).

Changes:
- Add flag parsing in the `case` block.
- Add `LINUX_KERNEL_BRANCH` env var default.
- When `--build-kernel` is passed, invoke `bin/omarchy-iso-build-kernel` before the Docker ISO build.
- When a cached kernel is present (and `--no-custom-kernel` is not set), mount `release/kernels/` into Docker and pass `USE_CUSTOM_KERNEL=1` env var.
- Append kernel version to ISO filename when custom kernel is included.

### 4. `builder/build-iso.sh` (modify)

Add a conditional block gated on the `USE_CUSTOM_KERNEL` env var:

- Copy the pre-built `linux-mainline-*.pkg.tar.zst` from `/custom-kernel/` into the offline mirror directory.
- Add it to the offline repo database via `repo-add`.
- Write a marker file `/root/omarchy_kernel_available` so the configurator knows the custom kernel is available.
- Create a writable copy of `archinstall.packages` that adds `linux-mainline` and `linux-mainline-headers`.
- Filter `linux-mainline` from the pacman download list (it's already in the offline mirror, not in any online repo).

No changes to the boot kernel, bootloader configs, mkinitcpio presets, or the default `arch_packages` array.

### 5. `configs/airootfs/root/configurator` (modify)

Update the kernel selection logic to detect Panther Lake hardware when the custom kernel is available:

```bash
# Use custom kernel for Panther Lake hardware when available in the ISO
if [[ -f /root/omarchy_kernel_available ]] && \
   lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'; then
  kernel_choice="linux-mainline"
elif lspci -nn 2>/dev/null | grep -q "106b:180[12]"; then
  kernel_choice="linux-t2"
else
  kernel_choice="linux"
fi
```

When `linux-mainline` is selected, add the offline repo to `custom_repositories` in the archinstall JSON so archinstall can find the package:

```json
"custom_repositories": [
  {
    "name": "offline",
    "url": "file:///var/cache/omarchy/mirror/offline/",
    "sign_check": "Never",
    "sign_option": "TrustAll"
  }
]
```

### 6. `.gitignore` (modify)

Add `release/kernels/` to keep built kernel packages out of version control.

---

## Build Usage

```bash
# Build the custom kernel (one-time, ~30-90min)
./bin/omarchy-iso-build-kernel

# Build ISO — auto-includes cached kernel if present
./bin/omarchy-iso-make

# Build kernel + ISO in one step
./bin/omarchy-iso-make --build-kernel

# Build ISO without the custom kernel
./bin/omarchy-iso-make --no-custom-kernel
```

## Install Flow

1. ISO boots with `linux-t2` kernel. Blacklist prevents Panther Lake audio panic.
2. Configurator detects hardware:
   - Panther Lake detected + custom kernel available -> `linux-mainline`
   - T2 Mac detected -> `linux-t2`
   - Everything else -> `linux`
3. archinstall installs the selected kernel from the offline mirror.
4. Installed system with `linux-mainline` has proper Panther Lake audio support (no blacklist needed).
5. Omarchy installer's `fix-dell-xps-audio.sh` skips the blacklist when `linux-mainline` is installed.

## Verification

1. **Regression**: `./bin/omarchy-iso-make` with no cached kernel produces identical output to today.
2. **Regression**: `./bin/omarchy-iso-make --no-custom-kernel` with a cached kernel produces identical output to today.
3. **Kernel build**: `./bin/omarchy-iso-build-kernel` produces `release/kernels/linux-mainline-*.pkg.tar.zst`.
4. **Custom kernel ISO**: `./bin/omarchy-iso-make` with cached kernel includes it in offline mirror.
5. **Panther Lake install**: In VM, verify configurator selects `linux-mainline` when Panther Lake GPU is detected.
6. **Normal install**: In VM, verify configurator selects `linux` on non-Panther-Lake hardware.
7. **T2 install**: Verify T2 detection still works and selects `linux-t2`.

## Removal Checklist (When Arch Upstreams the Fix)

Once the Arch `linux` package config includes all required Panther Lake options:

1. Delete `configs/kernel/xps-pantherlake.config`.
2. Remove Panther Lake detection block from `configs/airootfs/root/configurator`.
3. Delete `configs/airootfs/etc/modprobe.d/blacklist-panther-lake-audio.conf`.
4. Remove `fix-dell-xps-audio.sh` from the omarchy installer.
5. Optionally remove `--build-kernel` / `--no-custom-kernel` flags and `bin/omarchy-iso-build-kernel` if no other platforms need custom kernel builds. Or keep the infrastructure for future use.
