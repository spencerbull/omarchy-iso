# N1x Bring-up ISO

> Comprehensive restart context and the ordered recovery procedure are in
> [`N1X_HANDOFF.md`](N1X_HANDOFF.md). Current verdict: the USB installer works,
> but both installed Limine UKIs black-screen before any confirmed shell/SSH.

## Goal and done criteria

- Build a distinct AArch64 N1x ISO using NVIDIA's signed 7.0 kernel lineage.
- Do not preload the NVIDIA driver in the installed initramfs.
- Provide normal and console/SSH rescue Limine entries.
- Provide an installer-media recovery entry that never launches the installer,
  provisions key-only SSH, and records boot evidence even without a framebuffer.
- Pass focused source tests, build matching kernel/header packages, build and checksum the ISO, and stage it on UNAS.
- Physical N1x boot, exact PCI identity, display, and driver validation remain human gates.

## Streams and ownership

- Packages: `/home/sbull/omarchy-repos/omarchy-pkgs-linux-gb10`, branch `linux-gb10`, existing tracked changes preserved.
- Installer: `/home/sbull/omarchy-repos/omarchy-gb10-installer`, branch `gb10-installer-kernel`, existing tracked changes preserved.
- ISO: `/home/sbull/omarchy-repos/omarchy-iso-gb10-dev`, branch `gb10-dev-installer-iso`, existing tracked changes preserved.
- Builder: Coleman via `tailscale ssh dell@coleman`; no production repository publication.
- Cleanup owner: this Codex session for build staging and temporary extraction paths it creates.

## Allowed and forbidden actions

- Allowed: scoped source edits in the three checkouts above, local tests, remote build staging on Coleman, artifact transfer to UNAS.
- Forbidden: modifying the user-owned `TODO.md` files in the package and installer checkouts, touching the dirty XPS checkout, publishing packages, flashing firmware, or claiming hardware support before physical validation.

## Gates

- [x] Verify the NVIDIA 7.0 signed tag, source hashes, exported ARM64 configuration, and package metadata.
- [x] Add and statically validate `linux-n1x` and `linux-n1x-headers`.
- [x] Select `linux-n1x` throughout the AArch64 installer and ISO closure.
- [x] Remove installed early NVIDIA module injection and forced KMS for N1x.
- [x] Generate a compact console/SSH rescue Limine entry and automated hardware probe.
- [x] Pass package, installer, and ISO focused tests.
- [x] Build and inspect AArch64 kernel/header artifacts on Coleman (`linux-n1x` 7.0.14.nvidia1018-1; ARM64 magic `41524d64`).
- [x] Build, inspect, checksum, and stage the N1x ISO on UNAS (`09c2556c8d256358aae27e7ca26c3741b9f64fb59a4e3760394886ce5f343063`).
- [x] Record failed physical gate: installed `linux-n1x-rescue` reached a black
  panel, so a GPU-disabled boot cannot be treated as a visible-console path.
- [x] Add a visible, non-installing N1x USB recovery menu entry with early input,
  verbose console settings, automatic probe capture, Ethernet DHCP, and key-only
  root SSH at `omarchy-n1x-rescue.local`.
- [x] Harden the installed recovery UKI with explicit early keyboard modules,
  network services, conservative display parameters, and key-only user SSH.
- [x] Rebuild, inspect, checksum, and stage the recovery-hardened N1x ISO
  (`d2e2d0bab93991a54bbdbd267fdb42a902f61bd679f73b5c6a267cb89cc0a803`,
  5,041,022,976 bytes).
- [x] Read the installed `limine.conf` from the USB GRUB shell; root cause is the
  shared entry cmdline (rescue overridden through EFI load options), prepended
  `+=` ordering putting `quiet loglevel=0` last, and no `console=tty0` on a
  kernel defaulting to the SPCR serial console (2026-09-03).
- [x] Fix installer Limine finalization (`console=tty0 acpi=nospcr`, delete quiet
  defaults, `KERNEL_CMDLINE[linux-n1x-rescue]`, post-generation verification)
  and add `acpi=nospcr` to the USB recovery entry; all four focused suites pass.
- [x] Build, inspect, checksum, and stage the `recovery4` ISO on UNAS and locally
  (`0ded0c1844c2ab100eb40f4a689c4146fea03ab877e92b53d2b696bc3d508a26`,
  5,038,630,912 bytes; also at `~/Downloads/`).
- [x] Human gate passed: `recovery4` installed; `linux-n1x-rescue` shows the LUKS
  prompt and a text login on the panel; SSH reached as `sbull@192.168.1.254`.
- [x] Hardware identity captured: Dell XPS 16 DX16263, GPU `10de:2e06`, NVMe
  `1c5c:1f69`, MT7925 Wi-Fi, no internal wired NIC, SPCR serial console present.
- [ ] Boot the normal entry and validate NVIDIA/Hyprland.
- [x] Kernel: N1x I2C controllers (`NVDA0200`) are MediaTek MT8901 IP; carried
  NVIDIA 26.04 SAUCE commits `1e2a75fb7d0f` (i2c-mt65xx ACPI) and `c8ca6b82aeb7`
  (gpiolib debounce) in `linux-n1x` `pkgrel=2`; built on Coleman
  (`7.0.14-2-n1x`), installed on the target with `pacman -U`, rescue UKI
  rebuilt by hand (2026-09-03 16:51).
- [x] Reboot into `linux-n1x`: internal keyboard and touchpad now work.
- [x] NVIDIA GSP boot: fixed by BIOS 1.0.4 (2026-09-11); 610.57.04 initializes
  the GPU and `nvidia-smi` works. Never FLR the GPU (hangs the SoC).
- [ ] Panel on NVIDIA KMS (`nvidia_drm modeset=1 fbdev=1`) under test; then make
  `install/hardware/n1x.sh` firmware-aware (blacklist only on 0.x BIOS).
- [x] Interim desktop: NVIDIA stack blacklisted on the target, Hyprland renders
  in software on simpledrm with working internal keyboard/touchpad (recovery5
  install, 2026-09-03 20:50).
- [ ] Decide whether the N1x installer ships the NVIDIA blacklist (with `install`
  overrides) by default, and how to handle hyprlock/hypridle while rendering in
  software (hyprlock draws nothing, so idle lock looks like a black screen).
- [x] Refreshed `package-bundle` with pkgrel 2 and built `recovery5`
  (`d68bd5243418d4d69e3346b970cca742626b61ab8fdeb4ba1e1356d23ea91735`, 5,040,580,608
  bytes); staged on UNAS and copied to `~/Downloads/`.
- [ ] Installer/hook: make the `linux-n1x-rescue` UKI follow kernel upgrades.
- [ ] Kernel: FF-A EC driver does not match this firmware (`ARML0002`, FFH
  offset 2, no notify partition); battery/lid/thermal/UCSI remain broken.

## Open risks

- Target PCI device ID is unknown; public 610.57.04 explicitly lists N1x `2e03`/`2e06`, while NVIDIA test hardware also uses pre-release `2e2a` with a 615-series driver.
- NVIDIA's public open-driver repository does not currently provide a 615-series source tag, so 7.0 plus 610.57.04 remains an experimental public-source pairing.
- Coleman confirms its working Ubuntu environment has no registered firmware
  framebuffer and obtains display from NVIDIA DRM. The N1x GPU-disabled recovery
  path may intentionally remain black; Ethernet SSH is therefore the acceptance
  path until the target PCI identity and a binding driver are known.

## Quattro port ledger (branch `n1x-quattro`, both forks)

- [x] Preserve old branches as WIP commits and push to forks; sync fork
  `quattro` branches to upstream; create `n1x-quattro` worktrees.
- [x] ISO step 1-3: `--arch aarch64 --platform n1x --package-dir`, builder
  overlay, archiso arm64 patches, GRUB templating + N1x recovery entry,
  `test/unit/aarch64-build-test.sh`; quattro unit suite green.
- [x] Bundle: aarch64 builds of herdr, omacalc, omacut, omawrite, ttfx,
  obsidian, ttf-jetbrains-mono-nerd-basic added to `package-bundle` (120
  archives, `SHA256SUMS` verifies).
- [x] ISO step 4: configurator picks `linux-<platform>`, `limine_aa64.efi`, ALARM
  mirror on aarch64; orchestrator derives `BOOTAA64.EFI`/`limine_aa64.efi` from
  the machine architecture. No archinstall patch needed: quattro installs Limine
  itself. `tzupdate` no longer used by the configurator.
- [x] Runtime step 5 (`omarchy-n1x-quattro`): `bin/omarchy-hw-n1x`,
  `install/hardware/n1x.sh`, NVIDIA carve-out, aarch64 initramfs hooks/modules,
  ALARM pacman config, arch-aware Node tarball, `test/shell.d/hw-n1x-test.sh`.
  Deferred: ARM guards on `omarchy-update`-family commands (no aarch64 package
  channel yet), a pacman hook so the rescue UKI follows kernel upgrades.
- [ ] Limine entry-tool ordering, measured on the target: drop-in `+=` fragments
  come after `/etc/default/limine` fragments; among drop-ins the alphabetically
  first file's fragment lands last. `BOOT_ORDER` is last-file-wins.
- [ ] Build on Coleman with `--local-source <omarchy-n1x-quattro> <omarchy-pkgs>`
  and `--package-dir`, install on the laptop, validate. Build loop so far
  (`/home/dell/omarchy-gb10-builds/n1x-quattro/quattro-n1x-build{1..4}.log`):
  1 died on the zstd-only glob in `build-omarchy-packages.sh` (ALARM emits
  `.pkg.tar.xz`); 2 on `mise-bin`/`dell-xps13-sidecar-amps` not existing for
  aarch64; 3 on the shipped manifests being unfiltered for the expected-package
  count (and they would have broken pacstrap the same way). All fixed and
  pushed. Build 3's local makepkg printed `libfakeroot internal error: payload
  not recognized!` without failing; watch whether the built omarchy-dev is
  complete.
  Build 4 succeeded (`omarchy-2026.09.04-aarch64-n1x-local.iso`,
  `c2f3620378507c971f20d1695a034f78853fc19477eb921b077684f15dfd5d90`);
  omarchy-dev is complete. Physical install test pending.
