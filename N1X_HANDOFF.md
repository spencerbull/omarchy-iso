# N1x Omarchy bring-up handoff

Last updated: 2026-09-03 afternoon (US/Central)

## Read this first

Current verdict: **root cause of the installed black screen identified from the
installed `limine.conf`; fix implemented in source; `recovery4` ISO rebuilt for
a fresh install. Physical confirmation still pending.**

- The AArch64 USB ISO boots on the physical N1x system and the Omarchy
  installation flow completes. The install is LUKS encrypted
  (`cryptdevice=PARTUUID=46122c52-8b1f-464b-865b-22e16871e6f0:root
  root=/dev/mapper/root rootflags=subvol=@ rootfstype=btrfs`).
- With the USB removed, Limine starts from the installed disk and shows both
  generated entries. Selecting either produced a black panel.
- From the USB GRUB command line (`search --file --set=esp
  /EFI/limine/limine_aa64.efi`, then `cat ($esp)/limine.conf`) the installed
  config was read without touching the disk. It proved three defects, all in
  the installer's Limine finalization:
  1. Both entries carried the **same** `cmdline:` line. Limine passes that line
     to the UKI as EFI load options and systemd-stub prefers load options over
     the embedded `.cmdline`, so the rescue UKI's `console=tty0`, `nomodeset`,
     NVIDIA blacklist, and `systemd.unit=multi-user.target` were discarded. The
     "rescue" entry was the normal entry under another name.
  2. limine-entry-tool **prepends** `+=` lines. The verbose override ended up
     first and `quiet splash loglevel=0 systemd.show_status=false` landed after
     it, so both entries booted quietly.
  3. No entry named `console=tty0`. The N1x kernel is built with
     `CONFIG_CMDLINE="console=ttyAMA0"` and `CONFIG_ACPI_SPCR_TABLE=y`, so on
     firmware with an SPCR table the console, and therefore the LUKS passphrase
     prompt and any initramfs emergency shell, go to a serial UART while the
     panel stays black. This step is inferred, not proven; it fits both entries
     failing identically.
- Handoff item 6 in the failure history was wrong: Limine draws its menu, so the
  firmware does expose a GOP framebuffer, and `DRM_SIMPLEDRM=y` plus
  `FRAMEBUFFER_CONSOLE=y` are built in. A GPU-disabled boot is not expected to
  be black on its own.

The fix lives in the installer's `install/login/limine-snapper.sh` and is
embedded in the `recovery4` ISO. The user chose to rebuild and reinstall rather
than repair the existing disk in place. See [Built artifacts](#built-artifacts).

Immediate resume action: write the `recovery4` ISO to USB, install, remove the
USB, and boot the `linux-n1x-rescue` entry. Expect kernel text on the panel
followed by a LUKS passphrase prompt, then a text login with SSH available.

## Goal

Bring up a complete Omarchy installation on the pre-release NVIDIA N1x system,
without incorrectly treating it as the already-understood Coleman GB10 system.
The immediate milestone is a reliable first boot into at least a multi-user
shell with SSH. The final milestone is normal Omarchy graphical boot with the
internal input devices, storage, wired networking, and a correctly binding
NVIDIA driver.

### Done criteria

- The USB remains reproducibly bootable on AArch64 UEFI and can be used as a
  non-installing diagnostic environment.
- The installed disk boots without the USB into a multi-user shell and SSH.
- The exact first-boot failure is identified from the installed ESP, UKI,
  initramfs, root mapping, or retained journal rather than inferred from a
  black panel.
- The installed normal and recovery boot paths use the correct N1x kernel,
  root UUID/PARTUUID, Btrfs subvolume, encryption mapping when applicable, and
  required early modules.
- Plymouth remains absent from the AArch64 initramfs until its two confirmed
  AArch64 crashes are understood or an updated version is proven safe.
- The exact N1x PCI identity is captured. The NVIDIA driver is only enabled
  after verifying that the available driver actually supports that device.
- The internal keyboard, display, wired network, cold boot, warm reboot,
  suspend/resume, rollback entry, and Omarchy graphical session pass physical
  validation.
- Source changes are reviewed, committed, and pushed only after the user
  explicitly authorizes those repository actions.

## Critical boot-path distinction

The working and failing paths are different:

```text
Working USB path
UEFI -> GRUB AA64 -> raw vmlinuz-linux-n1x + live initramfs -> Archiso -> installer

Failing installed path
UEFI -> Limine AA64 -> EFI-chainloaded generated UKI -> installed root
```

The USB success is strong evidence that the raw N1x kernel can start this
hardware. It does **not** prove that the generated UKI has the correct embedded
command line/initramfs, that Limine can chainload that UKI correctly on this
firmware, or that the installed root can be located and mounted.

Both installed Limine entries use the installed kernel/initramfs generation
machinery and UKI/EFI handoff. Their shared black-screen failure moves the
investigation toward that common boundary. A raw-kernel GRUB installation on
disk is the leading fallback because it would deliberately reproduce the USB
boot mechanism that is already known to work.

## Quattro port (started 2026-09-03 evening)

The user chose to re-base the N1x work onto the `quattro` branches of both
repos, on their forks, staying current with upstream. Divergence made a
literal `git rebase` impractical (ISO: 9 ours vs 201 quattro; installer: 1
real commit vs 1640, 32 overlapping files, `install.sh` and
`install/login/limine-snapper.sh` no longer exist upstream), so the N1x
feature set is being re-applied by hand onto fresh branches.

| Stream | New worktree | Branch | Base | Pushed to |
| --- | --- | --- | --- | --- |
| ISO | `/home/sbull/omarchy-repos/omarchy-iso-n1x-quattro` | `n1x-quattro` | `omacom-io/omarchy-iso` quattro `2673c61` | `spencerbull/omarchy-iso` (remote `fork`) |
| Installer/runtime | `/home/sbull/omarchy-repos/omarchy-n1x-quattro` | `n1x-quattro` | `omacom/omarchy` quattro `f99d33a8` | `spencerbull/omarchy` (remote `origin`) |

The previous dirty trees were preserved as WIP commits and pushed to the
forks: ISO `gb10-dev-installer-iso` @ `d624082`, installer
`gb10-installer-kernel` @ `7ce32b60`. The forks' `quattro` branches were
created/fast-forwarded to upstream on 2026-09-03. The ISO fork's default
branch `main` was left untouched.

Port order (each step: quattro test suite + ours, then commit):

1. ISO build entrypoint and builder: arm64 container, Arch Linux ARM mirrors
   and keyring, `--arch aarch64` per upstream `plans/aarch64-support.md`, plus
   an N1x platform overlay and the offline kernel `--package-dir` input.
2. ISO archiso arm64 patches: GRUB module filter, mkinitcpio hook and early
   input modules, EFI-stubbed Image acceptance, no Plymouth on aarch64.
3. ISO GRUB templating: N1x recovery entry (`acpi=nospcr`, SSH key, probe).
4. ISO configurator: aarch64 kernel choice (`linux-n1x`), ALARM servers,
   `limine_aa64.efi`, archinstall aarch64 patches.
5. Runtime: `linux-n1x` transition, early input modules, Limine cmdline fixes
   (`console=tty0 acpi=nospcr`, no quiet, per-kernel rescue cmdline with
   verification), N1x carve-out in `install/hardware/nvidia.sh` (no early KMS,
   interim NVIDIA blacklist with `install` overrides), recovery SSH and probe,
   ALARM pacman config, aarch64 Node.js handoff, ARM lifecycle guards.
6. Build with `--local-source` on Coleman using `omarchy-pkgs-linux-gb10` as
   `/omarchy-pkgs`; install on the laptop; validate.

Source of truth for the features: `git diff abbd9ed d624082` in the ISO repo
and `git diff 9cf18525 7ce32b60` in the installer repo (merge-base to WIP).

## Worktrees, branches, and ownership (pre-port layout)

All N1x changes below are currently uncommitted overlays on the listed heads.
The HEAD values alone do not contain the current N1x work.

| Stream | Worktree | Branch | HEAD | State |
| --- | --- | --- | --- | --- |
| ISO and this handoff | `/home/sbull/omarchy-repos/omarchy-iso-gb10-dev` | `gb10-dev-installer-iso` | `7b5e92a82f0fd624913b855832cc3fdf42f8763c` | Dirty, task-owned N1x changes |
| Installer | `/home/sbull/omarchy-repos/omarchy-gb10-installer` | `gb10-installer-kernel` | `88e57e27121ee81393bbfab5ddaf039b9049cd0f` | Dirty, mixed prior GB10 plus current N1x changes |
| Packages | `/home/sbull/omarchy-repos/omarchy-pkgs-linux-gb10` | `linux-gb10` | `01f0e735ed9af605f1a52ffd081dbd97ad6c9e03` | Dirty, current N1x package work |
| Original XPS checkout | `/home/sbull/src/github.com/josephjacks/omarchy-iso` | `turbo-dell-xps-profile` | `537515e1d83b7a0f9972ed97cb8a94e0bf49be1b` | User-owned; do not touch |

The original XPS checkout currently contains these user-owned untracked files:

```text
configs/airootfs/usr/share/omarchy-iso/turbo/profiles/dell-xps-14-da14260.json
xps-hardware.json
```

Use the existing N1x/GB10 worktrees. Do not switch the original XPS checkout,
reset any tree, clean untracked files, or move changes between worktrees.

The `TODO.md` files in the installer and package worktrees predate this N1x
physical bring-up and contain historical GB10 scope. Preserve them as
user-owned history. `N1X_HANDOFF.md` and the ISO worktree's `TODO.md` are the
current N1x sources of truth.

### Current ISO worktree changes

Tracked modifications:

```text
bin/omarchy-iso-make
builder/archiso-aarch64-mkinitcpio.sh
builder/build-iso.sh
builder/gb10-omarchy-source.sh
builder/limine-hook.sh
configs/airootfs/root/.automated_script.sh
configs/airootfs/root/configurator
configs/grub/grub.cfg
configs/grub/loopback.cfg
configs/pacman-online-gb10.conf
configs/profiledef.sh
test/gb10-build-mode-test.sh
test/gb10-node-handoff-test.sh
```

Untracked task files:

```text
TODO.md
N1X_HANDOFF.md
builder/grub-platform.sh
builder/linux-n1x.preset
builder/n1x-recovery-authorized-key
builder/n1x-recovery-sshd.conf
configs/airootfs/usr/local/sbin/omarchy-n1x-live-probe
```

### Current installer worktree changes

Tracked modifications:

```text
install.sh
install/config/all.sh
install/config/hardware/nvidia.sh
install/config/hardware/nvidia/gb10-kernel.sh
install/helpers/errors.sh
install/login/limine-snapper.sh
install/preflight/guard.sh
install/preflight/show-env.sh
test/omarchy-hw-nvidia-gb10-test.sh
```

Untracked N1x files:

```text
install/config/hardware/nvidia/n1x-kernel.sh
install/config/hardware/nvidia/n1x-probe
install/config/hardware/nvidia/n1x-recovery.sh
```

### Current package worktree changes

Tracked modifications:

```text
build/gpg-keys.txt
pkgbuilds/limine-mkinitcpio-hook/.omarchy/package.json
pkgbuilds/limine-mkinitcpio-hook/PKGBUILD
```

Untracked N1x package files:

```text
pkgbuilds/linux-n1x/.omarchy/package.json
pkgbuilds/linux-n1x/PKGBUILD
pkgbuilds/linux-n1x/README.md
pkgbuilds/linux-n1x/Ubuntu-nvidia-7.0-7.0.0-1018.18_24.04.1.tag
```

## Safety and authorization boundaries

Allowed for this bring-up:

- Read and edit the three isolated worktrees above.
- Run focused tests and build unsigned local packages/ISOs.
- Use Coleman as an isolated build/reference host through
  `tailscale ssh dell@coleman`.
- Stage large artifacts on `/home/sbull/UNAS` through a hidden `.partial` file,
  compare local and remote hashes, and reveal the final filename only after an
  exact match.
- Boot the user-selected USB and inspect the target installation read-only.

Not authorized without a fresh explicit user request:

- Resetting, cleaning, deleting, staging, committing, pushing, merging, or
  opening PRs for the dirty trees.
- Modifying the original XPS checkout or the installer/package historical
  `TODO.md` files.
- Reinstalling or wiping the target disk before the current installation is
  inspected.
- Publishing packages, signing a repository, changing firmware, flashing a
  device, or claiming N1x support from artifact checks alone.
- Copying Coleman-specific UART addresses or Tegra/GB10 kernel arguments onto
  the N1x target without target evidence.

## Hardware and upstream facts

### Captured from the installed system on 2026-09-03 (recovery4, rescue entry, SSH)

- Machine: Dell Inc. XPS 16 DX16263, board 0261Q6, BIOS 0.60.1 (2026-03-02,
  pre-release Insyde/EDK2 firmware). Hostname chosen at install: `grace`.
  Installed user: `sbull`. Wired address during bring-up: `192.168.1.254`
  through a USB Realtek `r8152` dongle (`enu1`); there is no internal wired
  NIC. Wi-Fi is MediaTek MT7925 (`14c3:7925`, driver `mt7925e` binds).
- SoC: 18x Cortex-X925, 21 GiB RAM, SMCCC SOC_ID `jep106:0426:8901`.
- GPU: `000f:01:00.0` `10de:2e06` GB20B "RTX Spark N1X", Dell subsystem
  `1028:0d8e`. The pinned 610.57.04 open driver lists this ID; DKMS built the
  modules for `7.0.14-1-n1x`. Not yet exercised: the rescue entry blacklists
  it. Boot display comes from GOP -> `simpledrm` (`/dev/dri/card0`).
- Storage: SK hynix PVC10 512 GB NVMe (`1c5c:1f69`), driver `nvme`. Layout:
  `nvme0n1p1` 2 GiB ESP at `/boot`, `nvme0n1p2` LUKS
  (`PARTUUID=f073914b-b386-4b56-b181-61ea375509ee`) -> `/dev/mapper/root`
  Btrfs subvol `@`.
- Firmware publishes an ACPI **SPCR** table: `uart,mmio32,0x16a00000,115200`.
  Without `acpi=nospcr` the kernel takes that UART as console. This is the
  proven mechanism behind the earlier black screens.
- **Internal keyboard, touchpad, and touch panel do not work.** Only the
  external USB keyboard appears. Decompiled DSDT (iasl) shows three
  HID-over-I2C devices (`PNP0C50`): keyboard `\_SB.I2C2.ECKB` (`NCT9640`,
  address 0x05), touchpad `\_SB.I2C3.TPD0` (`DELL06CB`, 0x2C), and touch
  panel `\_SB.I2C1.TPL0` (`HIMX5200`, 0x4F). The seven controllers are ACPI
  `NVDA0200` with two register windows each and pins on `\_SB.GIO0`.
  **These are MediaTek I2C controllers, not Tegra:** the N1x CPU-side
  peripherals are MediaTek IP (GPIO `NVDA9221` binds `pinctrl-mt8901`, UART
  `NVDA0240` binds `8250_mtk`). No driver in the pinned kernel matches
  `NVDA0200`. NVIDIA's `26.04_linux-nvidia` branch is exactly our pinned base
  plus three commits, two of which are the fix:
  `1e2a75fb7d0f925eab94fd32e62fe6147d954ea1` "i2c: mediatek: Add ACPI/MT8901
  support and firmware-managed clocks" (adds `NVDA0200` -> `mt8901_compat`,
  124.8 MHz parent clock) and `c8ca6b82aeb7c0bd94f1b76e9c1880255114faed`
  "gpiolib: acpi: route acpi_dev_gpio_irq_wake_get_by() debounce through the
  warn-only wrapper" (the installed log shows the exact `Failed to set
  debounce-timeout 0: -22` this fixes, which would otherwise break the HID
  GPIO interrupts). Both are carried as patches in the `linux-n1x` package
  (`pkgrel=2`).
- **Embedded controller is unreachable.** Every ACPI EC method
  (`\_SB.ECRB`, `\_SB.ECWB`, `\_SB.FFA0.ECG5`) aborts with `AE_ERROR` from
  the FunctionalFixedHW region handler, so battery, AC, lid, thermal zones,
  and USB-C UCSI all fail. Cause, from source: the DSDT's FFH region uses
  offset 2 and exposes the FF-A device as `ARML0002`; NVIDIA's built-in
  `nvidia-ffa-ec` driver (`CONFIG_NVIDIA_FFA_EC=y`) only binds ACPI
  `MSFT000C`, only serves FFH offset 4, and only registers after a separate
  "notify service" partition `b510b3a3-...` probes, which this firmware does
  not expose. The firmware does expose the eight EC service partitions the
  driver knows (partition `0x8003`). No public NVIDIA branch differs. This
  follows a newer Open Device Partnership secure-EC spec revision than the
  driver implements. Not required for graphical boot; needed for power and
  lid state later.
- **NVIDIA GPU init fails on 610.57.04 (normal entry, 7.0.14-2-n1x, 2026-09-03
  17:07).** The `nvidia` module binds `10de:2e06`, `nvidia-drm` registers
  `card1`/`renderD128`, DKMS built cleanly, but RM cannot boot the GSP:
  `GspStatusQueueInit: msgqRxLink failed: -7` then repeated
  `ksec2PrepareBootCommands_GB20B: FWSEC timed out processing COT command`,
  `RmInitAdapter failed! (0x62:0x65:2119)`. `nvidia-smi` reports no devices.
  The GPU shows `DevSta: CorrErr+ UnsupReq+`. Hyprland then aborts because
  the only render node is the dead GPU (`MESA-EGL: failed to create dri2
  screen` for `10de:2e06`), and SDDM loops. The internal keyboard and
  touchpad enumerate fine on this kernel (`NCT9640:00 Keyboard`,
  `DELL06CB:00 Touchpad` via `i2c-hid` on `NVDA0200:02`/`:03`); the touch
  panel `HIMX5200` has ACPI `_STA` 0 and is intentionally absent.
  Coleman (Spark, `10de:2e12`) boots its GSP on open driver 580.178.04 with
  cmdline `iommu.passthrough=0 pci=pcie_bus_safe
  initcall_blacklist=simpledrm_platform_driver_init`; both machines show the
  same `0.000 Gb/s ... x0 link` line and 4 KiB pages, and both GPUs sit in
  a `DMA` IOMMU group. Public drivers top out at 610.57.04 (ALARM `extra`,
  GitHub tags); no 615 exists publicly. Untested candidates, in order:
  `pci=pcie_bus_safe`, `iommu.passthrough=0`, blacklisting `nvidiafb`
  (loaded alongside `nvidia`; a blacklist file was written to
  `/etc/modprobe.d/nvidiafb-blacklist.conf` on the target), then the 580
  series driver Coleman uses, then treating this pre-release board as
  needing NVIDIA's unreleased 615 stack.
- **Interim desktop achieved (2026-09-03 20:50, fresh recovery5 install,
  `grace` at `192.168.1.6`).** With the NVIDIA stack unloaded, Aquamarine
  starts on `/dev/dri/card0` (simpledrm) and Hyprland 0.56.1 runs with a
  1920x1200@60 output and software rendering; SDDM autologin works and the
  internal keyboard and touchpad are live. Persisted on the target as
  `/etc/modprobe.d/n1x-nvidia-disable.conf` (blacklists `nvidia`,
  `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`, `nvidiafb`). Without it,
  Aquamarine picks the framebuffer for output but falls back to the dead
  NVIDIA render node (`renderD128`) for rendering and Hyprland aborts;
  `AQ_DRM_DEVICES=/dev/dri/card0` alone does not help. Not yet in the
  installer: decide whether N1x installs should ship this blacklist until a
  driver that boots the GPU exists.
- **hyprlock is invisible under software rendering.** Omarchy's hypridle locks
  after 152 s; hyprlock then fails EGL (`failed to create dri2 screen`,
  `EGL setup failed, disabling glamor`) and draws nothing, so the panel goes
  black while the session behind it is fine. Typing the password blind still
  unlocks. hypridle was killed for the test session on 2026-09-03 21:26; a
  durable fix (hyprlock software path, or disabling the lock timeout on N1x
  while the GPU is unusable) is still needed. Also observed: something in the
  Omarchy session start explicitly loads the NVIDIA modules despite
  `blacklist`, so the target's modprobe file also carries
  `install <module> /bin/false` lines.
- Pitfall for scripts on the target: a `sudo -S` helper fed by `echo pass |`
  replaces stdin, so `printf ... | sudo tee` and heredocs write empty files.
  Use `sudo sh -c 'printf ... > file'`.
- **Do not PCI function-reset the GPU.** Writing `1` to
  `/sys/bus/pci/devices/000f:01:00.0/reset` (`flr`) after unloading the
  NVIDIA modules hung the whole machine instantly (SSH dead, needed a power
  cycle) on 2026-09-03 ~17:15. The GPU is on-package; treat it as
  non-resettable.
- `nvidia-ffa-ec` aside, FF-A itself works: driver and firmware both 1.2, and
  the TPM CRB partition binds.
- Kernel log noise that is benign or firmware-side: GPU DOE mailbox reset
  failures, thermal zones with invalid trip points, HID sensor DMA mask
  warnings, `BGRT` with a bad BMP magic.

Raw ACPI tables from the target are kept on Coleman at
`/home/dell/omarchy-gb10-builds/n1x-acpi/` (DSDT, SSDT1-3); decompile with
`iasl -d` in an Arch container (`pacman -S acpica`). dmesg and probe logs can
be re-captured over SSH at any time (`journalctl -b -k`,
`/var/log/omarchy-n1x-probe.log`).


- The target is a new/pre-release N1x system. It must not be locked to the
  Coleman GB10 DMI/PCI tuple. Its exact GPU and NIC PCI identities have not yet
  been captured.
- `linux-n1x` is based on NVIDIA's signed Ubuntu NVIDIA 7.0 lineage:
  - Ubuntu release: `7.0.0-1018.18~24.04.1`
  - tag: `Ubuntu-nvidia-7.0-7.0.0-1018.18_24.04.1`
  - signed tag object: `5a6b09b7d33204dcd973b1b509137e509b28309b`
  - source commit: `d76db97d0a41dba9bdacca29ff22a0bb511854a9`
  - upstream kernel base: `7.0.14`
  - package version: `linux-n1x 7.0.14.nvidia1018-1`
- The kernel uses NVIDIA's exported 4 KiB `arm64-nvidia` configuration and
  asserts ACPI, EFI, SimpleDRM, framebuffer console, PL011 serial console,
  I2C-HID, Mellanox, MediaTek, and Realtek `R8127` support. The built package
  contains `r8127.ko`, `r8169.ko`, and `mlx5_core.ko`.
- The development image pairs the kernel with public
  `nvidia-open-dkms=610.57.04-1`, `nvidia-utils=610.57.04-1`, and GSP firmware.
  That public driver explicitly lists N1x PCI devices `2e03` and `2e06`.
  Pre-release `2e2a` systems have been observed with a newer 615-series stack,
  for which no matching public open-driver source tag was available during
  this work. Display initialization is therefore still an open hardware gate.
- Coleman is a useful Ubuntu/GB10 reference, not proof for this N1x target.
  Coleman has no `/proc/fb` entry or `/sys/class/graphics/fb*`; its panel comes
  from NVIDIA DRM. Its working Ubuntu kernel command line includes platform-
  specific settings such as `initcall_blacklist=simpledrm_platform_driver_init`
  and a concrete UART MMIO address. Those were intentionally not copied to the
  unidentified N1x target.

## What has been implemented

### Kernel/package stream

- Added the explicit AArch64-only `linux-n1x` and `linux-n1x-headers` package
  split using the signed and pinned NVIDIA 7.0 source above.
- Installs the raw ARM64 `Image`, preserves the `ARMd` header, skips device
  trees because the observed systems use ACPI, and caps compilation at 12 jobs
  for QEMU stability.
- Fails closed when required N1x kernel options drift.
- Updated the Limine helper package metadata/build path for AArch64. The built
  `limine-mkinitcpio-hook 1.38.0-1` package was directly inspected and contains
  upstream multi-architecture EFI selection, including AA64 support.

### Installer stream

- Generalized the authorized ARM image path so N1x is selected explicitly and
  is not required to match the Coleman GB10 detector.
- Installs and validates `linux-n1x` plus headers before removing the generic
  Arch kernel.
- Writes `/etc/mkinitcpio.conf.d/n1x-input.conf` with:

  ```text
  MODULES+=(i2c_tegra i2c_hid i2c_hid_acpi hid_generic hid_multitouch usbhid)
  ```

- Removed forced early proprietary NVIDIA module injection/KMS for N1x.
- Omits the Plymouth hook on AArch64 and retains `plymouth.enable=0` as a
  runtime safeguard.
- Uses `snapper --no-dbus` because installer-chroot D-Bus was unavailable and
  caused `org.freedesktop.DBus.Error.ServiceUnknown` at the end of installation.
- Fixes the Limine finalization order so `/etc/default/limine` exists before
  package hooks run, avoids unnecessary double UKI rebuilds, and refuses to
  finish unless boot entries plus `limine_aa64.efi` and `BOOTAA64.EFI` exist.
- Creates a compact `linux-n1x-rescue` UKI and places it before the normal entry
  during experimental bring-up.
- (2026-09-03 afternoon) On AArch64, deletes the `quiet splash loglevel=0` line
  from `/etc/default/limine` instead of appending an override, adds
  `console=tty0 acpi=nospcr` to the default cmdline, writes
  `KERNEL_CMDLINE[linux-n1x-rescue]=` so the rescue entry carries its own
  console cmdline in `limine.conf`, verifies the rescue block after generation
  (rewriting it in place with awk if the per-kernel key was not honored), and
  fails closed if any generated AArch64 entry is quiet or lacks `console=tty0`.
- (2026-09-03 afternoon) The USB `N1x recovery shell + SSH` GRUB entry also
  gained `acpi=nospcr`.
- Installs an N1x probe, key-only SSH for the configured installed user, and
  enables `sshd`, `systemd-networkd`, `systemd-resolved`, and the probe service.
  Installed recovery deliberately has `PermitRootLogin no`; the configured
  username from the successful install has not yet been recorded.

### ISO stream

- Added `--n1x` selection and platform-aware kernel/package validation.
- Uses Arch Linux ARM mirrors/keyring and an AArch64 GRUB-only profile.
- Removes x86-only Archiso hooks and Plymouth from the live initramfs.
- Includes the early Tegra/I2C-HID modules needed by the internal keyboard.
  An external keyboard was required on an earlier ISO; the corrected input
  initramfs has artifact proof but still needs a fresh physical keyboard test.
- Added platform template rendering so N1x-only GRUB entries do not leak into
  GB10/x86 builds.
- Added a visible USB N1x recovery entry, key-only root SSH, Ethernet DHCP,
  hostname `omarchy-n1x-rescue`, and automatic probe output at
  `/var/log/omarchy-n1x-live-probe.log`.
- Corrected archiso permission normalization so live `/root/.ssh` is `0700`
  and `authorized_keys` is `0600` in the final image.
- The USB recovery entry disables NVIDIA and uses `nomodeset`; it may therefore
  be black on firmware with no framebuffer. For current diagnosis, use the
  normal USB entry with only the recovery marker appended.

## Failure history and lessons

1. The first AArch64 live boot showed `plymouthd` crashing in `strcmp()` at
   `main+0x11ec`.
2. A subsequent Plymouth attempt aborted in
   `ply_event_loop_watch_fd()` while attaching the boot server.
3. `plymouth.enable=0` alone did not prevent all early Plymouth execution, so
   the AArch64 live and installed initramfs generation now omits the hook.
4. The installer initially failed near completion because Snapper tried to use
   an unavailable system D-Bus. `snapper --no-dbus` fixed that boundary.
5. Limine was initially installed without usable entries. Installer ordering
   and entry validation were changed, and a later physical install displayed
   both normal and rescue entries.
6. A headless installed recovery was created by blacklisting NVIDIA. Coleman
   evidence later showed that these systems may have no firmware framebuffer,
   so a black panel is expected when graphics is disabled and cannot itself
   distinguish a working recovery from an early boot failure.
7. The final USB recovery image added SSH and probe capture. During the latest
   physical test, however, the user clarified that the black screen being
   discussed was first boot from the installed disk with no USB inserted.
8. Both installed Limine entries went black. Reading the installed
   `limine.conf` from the USB GRUB shell showed why: identical entry cmdlines
   (rescue overridden through EFI load options), `quiet loglevel=0` winning
   because the entry tool prepends `+=` lines, and no `console=tty0` on a
   kernel that defaults to the SPCR serial console. The USB installer looked
   healthy only because its TUI runs on a getty on tty1, which draws through
   fbcon regardless of where printk and `/dev/console` go.
9. Lesson: on AArch64 never rely on cmdline ordering in `/etc/default/limine`;
   delete conflicting defaults. Never assume a UKI's embedded cmdline is what
   Limine boots; verify the `cmdline:` line in `/boot/limine.conf`.

## Built artifacts

### Kernel pkgrel 2 (internal input fix), built 2026-09-03 16:46

```text
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/packages-src/build-output/edge/aarch64/
  linux-n1x-7.0.14.nvidia1018-2-aarch64.pkg.tar.xz
    sha256 3962ee83c0af5af3d30e7e06d19cd30879fc3ee54162d61a4ee2dc3936ad6d99
  linux-n1x-headers-7.0.14.nvidia1018-2-aarch64.pkg.tar.xz
    sha256 1413573e6583c4257622debde99cb52bed5d95509262c74ec3ab6431e3ee67da
build log: /home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/linux-n1x-pkgrel2-build.log
local copy: /home/sbull/.claude/jobs/1b7a6ae3/tmp/n1x-pkgrel2/ (job-scoped, temporary)
```

Kernel release string is `7.0.14-2-n1x`. Built with
`bin/repo build --arch aarch64 --package linux-n1x` from the rsync copy of the
package worktree at `.../packages-src` on Coleman. The `i2c-mt65xx.ko` in the
package carries `alias acpi*:NVDA0200:*`. Installed on the target with
`pacman -U` on 2026-09-03; DKMS rebuilt `nvidia/610.57.04` for the new kernel
and the Limine hook regenerated `omarchy_linux-n1x.efi`. The rescue UKI is a
custom entry and is **not** regenerated by the hooks on kernel upgrades; it was
rebuilt by hand this time. Open design gap: add a pacman hook or extend the
installer so `linux-n1x-rescue` follows kernel upgrades.

The `package-bundle` used by the ISO build still holds pkgrel 1; replace both
kernel archives and refresh `SHA256SUMS` before the next ISO build.

### Newest image: recovery5 (recovery4 + kernel pkgrel 2 with internal input fix)

```text
/home/sbull/UNAS/omarchy-2026.09.03-aarch64-n1x-n1x-recovery5-20260903.iso
size:   5,040,580,608 bytes
sha256: d68bd5243418d4d69e3346b970cca742626b61ab8fdeb4ba1e1356d23ea91735
build log: /home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/n1x-recovery5-iso-build.log
```

A byte-identical local copy is at
`/home/sbull/Downloads/omarchy-2026.09.03-aarch64-n1x-n1x-recovery5-20260903.iso`.

Inspected on Coleman: live kernel tree `7.0.14-2-n1x`, offline mirror carries
`linux-n1x-7.0.14.nvidia1018-2` and headers, GRUB recovery entry has
`acpi=nospcr`, embedded `limine-snapper.sh` identical to source. Installing
from this image gives the same state the target reached on 2026-09-03 17:07
(console fixed, keyboard and touchpad working, NVIDIA GSP still failing).

### Previous image: recovery4 (console and rescue-cmdline fix)

```text
/home/sbull/UNAS/omarchy-2026.09.03-aarch64-n1x-n1x-recovery4-20260903.iso
size:   5,038,630,912 bytes
sha256: 0ded0c1844c2ab100eb40f4a689c4146fea03ab877e92b53d2b696bc3d508a26
```

A byte-identical local copy is at
`/home/sbull/Downloads/omarchy-2026.09.03-aarch64-n1x-n1x-recovery4-20260903.iso`.

Remote build record:

```text
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/n1x-recovery4-iso-build.log
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/iso/release/omarchy-2026.09.03-aarch64-n1x-n1x-recovery4-20260903.iso
```

Build procedure used (Coleman holds rsync copies of both worktrees):

```bash
B=/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903
rsync -a --delete --exclude .git /home/sbull/omarchy-repos/omarchy-gb10-installer/ dell@coleman:$B/installer/
rsync -a --delete --exclude .git --exclude release/ --exclude .gitmodules /home/sbull/omarchy-repos/omarchy-iso-gb10-dev/ dell@coleman:$B/iso/
ssh dell@coleman "cd $B/iso && OMARCHY_PATH=$B/installer OMARCHY_INSTALLER_REF=n1x-recovery4-20260903 \
  bin/omarchy-iso-make --n1x --package-dir $B/package-bundle --local-source --no-boot-offer"
```

### Previous recovery-hardened image (recovery3, superseded)

```text
/home/sbull/UNAS/omarchy-2026.09.03-aarch64-n1x-n1x-recovery3-20260903.iso
size:   5,041,022,976 bytes
sha256: d2e2d0bab93991a54bbdbd267fdb42a902f61bd679f73b5c6a267cb89cc0a803
```

The ISO was streamed from Coleman to a hidden UNAS `.partial`, read back and
hashed locally, compared against Coleman's hash, and renamed only after the
hashes matched. No matching partial file remains.

Remote source/build records:

```text
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/package-bundle
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/n1x-recovery3-iso-build.log
/home/dell/omarchy-gb10-builds/n1x-7.0.14-20260903/iso/release/omarchy-2026.09.03-aarch64-n1x-n1x-recovery3-20260903.iso
```

Coleman access must use:

```bash
tailscale ssh dell@coleman
```

### Earlier image retained for comparison

```text
/home/sbull/UNAS/omarchy-2026.09.03-aarch64-n1x-n1x-7.0.14-20260903.iso
size:   5,040,685,056 bytes
sha256: 09c2556c8d256358aae27e7ca26c3741b9f64fb59a4e3760394886ce5f343063
```

Do not overwrite or delete either artifact.

An intermediate `n1x-recovery2` image was retained only in the Coleman build
area. Artifact inspection caught `/root/.ssh` and `authorized_keys` being
normalized to `0755/0644`; that image was not promoted to the final UNAS name.
The profile permissions were fixed and `recovery3` was rebuilt and inspected.

## Verification completed

Focused source checks passed after the final permission fix:

```bash
cd /home/sbull/omarchy-repos/omarchy-iso-gb10-dev
bash -n configs/profiledef.sh test/gb10-build-mode-test.sh
./test/gb10-build-mode-test.sh
OMARCHY_SOURCE_UNDER_TEST=/home/sbull/omarchy-repos/omarchy-gb10-installer \
  bash ./test/gb10-node-handoff-test.sh
git diff --check

cd /home/sbull/omarchy-repos/omarchy-gb10-installer
./test/omarchy-hw-nvidia-gb10-test.sh
git diff --check
```

The final `recovery3` artifact itself was inspected, not only its source:

- `/EFI/BOOT/BOOTAA64.EFI` is a PE32+ AArch64 EFI application.
- `vmlinuz-linux-n1x` is a raw ARM64 bootable `Image` with `ARMd` magic
  `41524d64` at byte offset 56.
- Direct and loopback GRUB configs pass `grub-script-check`, show a persistent
  menu, and contain both the normal installer and N1x recovery entries.
- The SquashFS checksum passes and the installed live package list contains
  `linux-n1x`, not `linux-gb10` or `linux-t2`.
- Live recovery contains the expected authorized-key fingerprint
  `SHA256:W7Cm7RfORmWRyDRuuMOpqgKZ0sKpkObsmraI40F5Ssg`.
- Live `/root/.ssh` is `0700`, `authorized_keys` is `0600`, passwords and
  keyboard-interactive authentication are disabled, and root is key-only.
- `sshd`, `systemd-networkd`, and `systemd-resolved` are enabled; the embedded
  network profile requests Ethernet DHCP and mDNS.
- The live recovery dispatcher exits to a shell instead of launching the
  configurator/installer and writes the N1x probe log.
- The embedded installer contains the N1x input, recovery, and Limine changes.
- The live initramfs contains `i2c-tegra`, `i2c-hid`, `i2c-hid-acpi`,
  `hid-generic`, and `hid-multitouch`; it contains no Plymouth payload and no
  proprietary NVIDIA kernel module.

These checks prove artifact composition. They do not prove installed UKI boot,
root-device discovery, display, networking, or driver binding on the target.

## Latest network evidence

After the installed Limine boot produced a black screen, the development host
checked both attached LANs:

- wired development-host address: `192.168.1.95/24`
- Wi-Fi development-host address: `192.168.10.204/24`
- `omarchy-n1x-rescue.local` did not resolve.
- No OpenSSH 10.5 live-image banner was found on `192.168.1.0/24`.
- `192.168.10.226` exposed OpenSSH 10.3, but the recovery key was rejected for
  both `root` and `sbull`; it was not identified as the target.

This proves only that no usable target SSH endpoint was discovered from the
development host. It does not prove whether the kernel stopped before
userspace, the installed NIC failed to bind, DHCP failed, the machine was on a
different segment, or the installed username was different.

## Current diagnosis

Confirmed:

- The physical target can boot the raw N1x kernel/initramfs from USB GRUB far
  enough to run the Omarchy installer.
- The installed AA64 Limine binary and its menu run.
- Both installed generated entries fail to produce visible output.
- The installed recovery is not expected to show graphics when NVIDIA is
  blacklisted and no firmware framebuffer exists.
- The normal installed entry also goes black, so rescue-only graphics flags
  are not the complete explanation.
- No useful installed-system SSH or journal evidence has been obtained.

Leading hypotheses, in the order they should be checked:

1. The UKI embeds an incorrect or incomplete root, encryption, UUID/PARTUUID,
   or Btrfs subvolume command line.
2. The installed initramfs lacks a storage, crypto, filesystem, or platform
   module needed before the real root is mounted.
3. Limine's EFI-chainload handoff to the generated AArch64 UKI is incompatible
   with this pre-release firmware/kernel combination even though the UKI was
   generated successfully.
4. The system reaches userspace but has neither a usable framebuffer nor a
   working NIC/DHCP path. This would explain the lack of both panel output and
   SSH without proving an early kernel failure.
5. The normal path reaches the installed root but the 610-series NVIDIA driver
   does not bind the target's unknown pre-release GPU.

Do not choose between these from the black panel alone.

## Resume runbook

### 1. Boot the USB into a non-installing shell using the working graphics path

Use the `recovery3` USB, wired Ethernet, and an external keyboard:

1. Insert the USB and choose it from the firmware boot menu.
2. At the USB GRUB menu, highlight the first entry:
   `Omarchy (aarch64, ...)`.
3. Do **not** choose `N1x recovery shell + SSH`; that entry intentionally uses
   `nomodeset` and blacklists NVIDIA, so it can remain black.
4. Press `e`.
5. Find the line beginning with:

   ```text
   linux /arch/boot/aarch64/vmlinuz-linux-n1x
   ```

6. Preserve every existing argument and append:

   ```text
   omarchy.n1x_recovery=1 systemd.unit=multi-user.target loglevel=7 ignore_loglevel
   ```

7. Do not append `nomodeset` or an NVIDIA blacklist.
8. Boot the edited entry with `Ctrl+X` or `F10`.

This edit is temporary and changes neither the USB nor the installed disk. The
recovery marker makes `/root/.automated_script.sh` run the probe and open a
login shell instead of starting the installer.

If a shell is visible, run:

```bash
systemctl restart systemd-networkd systemd-resolved sshd
ip -brief address
```

The live ISO accepts the local development key as root:

```bash
ssh -i /home/sbull/.ssh/id_ed25519 root@omarchy-n1x-rescue.local
```

If `.local` is unavailable, use the IPv4 address printed by `ip -brief
address` or identify the new OpenSSH 10.5 listener on the local wired subnet.

### 2. Capture live evidence before touching the installed disk

Run and save:

```bash
uname -a
cat /proc/cmdline
cat /sys/class/tty/console/active 2>/dev/null || true
cat /proc/fb 2>/dev/null || true
ip -brief link
ip -brief address
lspci -Dnnk
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS
blkid
efibootmgr -v
journalctl -b -k --no-pager
cat /var/log/omarchy-n1x-live-probe.log
```

This should finally capture the target GPU, NIC, storage controller, console,
and framebuffer identities.

### 3. Resolve exact installed partitions, then mount read-only

Do not guess device names. First identify:

- the installed EFI System Partition;
- the installed root filesystem or LUKS container;
- the Btrfs root subvolume name;
- whether `/boot` is the ESP or a separate filesystem.

If encryption is present, inspect it first with `cryptsetup luksDump`. Opening
it read-only may be necessary, but record the exact device before doing so.
Mount the resolved root and ESP beneath dedicated temporary paths with `-o ro`.
Do not chroot or regenerate anything during this pass.

### 4. Inspect the installed boot contract

Collect these files and listings from the mounted installation:

```text
ESP/limine.conf
ESP/EFI/limine/limine_aa64.efi
ESP/EFI/BOOT/BOOTAA64.EFI
ESP/EFI/Linux/*.efi
root/etc/default/limine
root/etc/fstab
root/etc/crypttab and root/etc/crypttab.initramfs when present
root/etc/mkinitcpio.conf
root/etc/mkinitcpio.conf.d/*.conf
root/etc/mkinitcpio.d/*.preset
root/usr/lib/modules/*/pkgbase
root/var/log/omarchy-install.log
root/var/log/journal/** when persistent journals exist
```

For each UKI:

- Record `stat`, SHA-256, and `file` output.
- Inspect PE sections with `objdump -h` or `ukify inspect`.
- Extract `.cmdline`, `.linux`, `.initrd`, `.osrel`, and `.uname` without
  modifying the source UKI.
- Confirm `.linux` has the ARM64 `ARMd` magic at its expected raw-image offset.
- Compare every embedded `root=`, `rd.luks.*`/`cryptdevice=`, UUID/PARTUUID,
  and `rootflags=subvol=` value with `lsblk`, `blkid`, `fstab`, and the actual
  Btrfs layout.
- Inspect the embedded initramfs with `lsinitcpio` and verify storage, crypto,
  Btrfs, I2C-HID, and USB-HID modules. Confirm Plymouth is absent.
- Compare the normal and rescue UKIs to determine which parts are actually
  shared.

Inspect retained boots read-only with the mounted journal directory. If no
failed-boot record exists, that is evidence that the failing path stops before
persistent journaling rather than proof of a clean boot.

### 5. Select the narrow repair from evidence

- **Wrong embedded command line:** correct `/etc/default/limine` or the source
  config, then regenerate the UKIs and validate their extracted `.cmdline`
  before rebooting.
- **Missing initramfs modules/hooks:** add only the proven missing modules,
  rebuild, inspect the produced initramfs/UKI, and retain the previous UKI.
- **Limine-to-UKI incompatibility:** install an AA64 GRUB entry alongside
  Limine that loads the raw `vmlinuz-linux-n1x` and initramfs from disk with the
  verified root command line. Preserve Limine as a fallback. This is the
  leading architectural fallback because it matches the working USB path.
- **Userspace boot with no display:** use SSH to capture the exact GPU ID and
  driver probe, then decide whether the available 610 driver can bind it.
- **NIC/DHCP failure:** use the captured PCI ID and kernel modules to fix the
  exact interface; do not infer `r8127`, `r8169`, or `mlx5` from the chassis
  name alone.

Any repair requires remounting the target read-write and possibly changing EFI
state. Stop after the read-only report and confirm the proposed target/files
with the user before performing that mutation.

## Remaining checkpoints

- [x] Pin and package the NVIDIA 7.0 N1x-era kernel and headers.
- [x] Build and inspect the matching AArch64 package pair.
- [x] Select `linux-n1x` through ISO and installer paths.
- [x] Remove Plymouth from AArch64 initramfs generation.
- [x] Add early internal/USB keyboard modules to the installed initramfs.
- [x] Fix installer Snapper D-Bus failure with direct mode.
- [x] Generate and validate AA64 Limine files and normal/rescue entries.
- [x] Build, inspect, checksum, and stage the recovery-hardened USB ISO.
- [x] Complete a physical ISO installation far enough to reach installed
  Limine with both entries.
- [x] Read the installed `limine.conf` from the USB GRUB shell without
  mounting the disk (2026-09-03).
- [x] Identify the installed first-boot root cause: shared entry cmdline,
  prepended `+=` ordering, and no panel console (2026-09-03).
- [x] Fix the installer's Limine finalization and rebuild the `recovery4` ISO.
- [x] Reinstall from `recovery4`, boot `linux-n1x-rescue`: LUKS prompt and
  text login appear on the panel; SSH works as `sbull@192.168.1.254`
  (2026-09-03 afternoon).
- [x] Capture exact target PCI/storage/network identities and probe log over
  SSH (see Hardware facts).
- [x] Boot the normal `linux-n1x` entry: internal keyboard and touchpad work
  on 7.0.14-2-n1x; NVIDIA binds but GSP boot fails (FWSEC COT timeout), so
  Hyprland aborts and SDDM loops (2026-09-03 17:07).
- [ ] Get the GPU to initialize: try `pci=pcie_bus_safe iommu.passthrough=0`
  and the `nvidiafb` blacklist; then the 580 driver; else hardware gate.
- [x] Interim usable desktop: NVIDIA stack blacklisted on the target; Hyprland
  runs in software on `simpledrm` (2026-09-03 20:50). Decide whether the
  installer ships this for N1x.
- [ ] Rebuild `linux-n1x` `pkgrel=2` with the two NVIDIA 26.04 SAUCE patches
  (MediaTek I2C ACPI + gpiolib debounce), install it on the target with
  `pacman -U` to validate keyboard/touchpad, then rebuild the ISO.
- [ ] Decide how to handle the FF-A EC gap (battery, lid, thermal, UCSI).
- [ ] Boot the installed system to multi-user plus SSH without the USB.
- [ ] Boot normal Omarchy and validate display, internal keyboard, networking,
  NVIDIA binding, cold/warm reboot, suspend/resume, and rollback.
- [ ] Run final source tests and independent review after the physical repair
  is reflected in source.
- [ ] Commit/push only if explicitly requested.

## Worker and review history

No worker or subagent was used for the 2026-09-03 N1x Plymouth/recovery/physical
boot iteration. The orchestrator made and inspected those changes directly.

The older GB10 baseline used Herdr workers and independent reviews; their
names, findings, and prior pushed checkpoints are preserved in the installer
worktree's historical `TODO.md`. Treat those reviews as evidence for the older
GB10 baseline only. They do not close the current physical N1x boot gate.

## Suggested prompt for the next session

```text
Resume the N1x Omarchy bring-up from
/home/sbull/omarchy-repos/omarchy-iso-gb10-dev/N1X_HANDOFF.md. First verify the
recorded branch, HEAD, and dirty state of all four worktrees; preserve every
existing change and do not touch the original XPS checkout. The installed
black screen was traced to the Limine entry cmdlines (rescue overridden via EFI
load options, quiet defaults prepended, no console=tty0); the installer fix is
in the recovery4 ISO on UNAS. Continue from the physical result of installing
recovery4 and booting linux-n1x-rescue. Do not commit, push, or publish
without explicit authorization.
```
