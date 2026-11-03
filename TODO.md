# OEM ISO

Goal: deliver a zero-touch full-disk OEM ISO and Tailshare download link.

Branch: `oem-iso`, based on `origin/quattro` at `ef1d3897f63f2e0104e461f7bf0d4bb0456168c9`. Checkout: `/home/sbull/.t3/worktrees/omarchy-iso/t3-055bbef0`. Initial checkout was clean.

Allowed: scoped code changes, tests, internal omabot review/fix loop, branch push, ISO build, disposable VM installs, Tailshare publication. Forbidden: production deployment, real disk installation, unrelated user changes, merging into quattro.

- [x] Add opt-in OEM build, retain boot logo/dashboard, automatically select the sole internal disk, use existing encrypted deferred-owner setup and successful-install reboot.
- [x] Run the full VM-free suite and omabot internal review; fix and recheck findings before building.
- [x] Build x86_64 OEM ISO and verify zero-keystroke installation and first-boot owner setup in a disposable VM.
- [x] Push `oem-iso`, publish ISO/checksum through Tailshare, report the link.

Disk policy: exactly one writable, unmounted, non-removable, non-hotplug internal disk of at least 32 GiB. Ambiguous or missing targets halt without a prompt or disk writes. Defaults are encrypted storage, US keyboard, English, UTC, hostname `omarchy`; the owner completes setup at first boot.

Review backend: omabot's `review` command. Implementation and verification owner: primary T3 Code agent. No implementation workers. Review evidence and build/VM artifacts will be recorded here.

Verification so far: shell syntax and `git diff --check` pass; `./test/all` passes (387 Python tests, three skips, and all shell tests). Omabot review round 1 identified missing `lsblk --tree`; reproduced with the installed lsblk, fixed, and a regression was proved by removing the fix and observing failure. Full suite passed again after restoring it. Review remains in progress; ISO build has not started.

Review round 1 (Codex XHigh via omabot) checked configuration, credentials/key injection, dashboard success/failure and naming; identified an eMMC ambiguity defect after the earlier mounted-tree and network-device fixes. Added MMC transport/card-type handling, SD exclusion and fail-closed unknown MMC metadata; the eMMC regression fails when its fix is removed. Focused omabot round 2 is reviewing the final selector. Reviewer reports: `/tmp/oem-iso-review/reports/`. Runtime verifier container `omarchy-oem-verifier` is ready; verifier script `/tmp/oem-iso-review/verify-oem.py` sends zero keys and attaches no network or cidata. User confirmed publication through the existing `https://taker.trout-rooster.ts.net` address.

Code gate passed: omabot round 2 (Codex XHigh) reported no actionable findings and cleared the ISO build. The primary agent ran all 392 Python tests (three skips), every shell test, shell syntax and whitespace checks on the final code. The reviewer independently checked mounted ancestry, local-storage filtering, MMC/SD classification and eMMC/NVMe ambiguity; three filesystem-backed MMC tests were blocked in its read-only sandbox, so it verified equivalent cases in memory. Those filesystem-backed tests passed in the primary agent’s full suite.

Publication: `oem-iso` code commit `d34a53adfab8c1b91d56f1e867c8fcd1e8ab2a82` is published at `https://github.com/spencerbull/omarchy-iso/tree/oem-iso`; upstream `omacom/omarchy-iso` denied this account write access. The existing personal fork accepted the branch over SSH (HTTPS OAuth lacked workflow scope for the newer quattro history). No pull request opened and nothing merged.

Build: stable-runtime attempt stopped because its published runtime lacks `install/provisioning/progress-icon.sh`, required by current quattro. Building with `--oem --edge --keep-pkg-cache --no-boot-offer` instead, whose runtime tracks quattro. The first edge attempt refused a stale shared-cache omarchy-keyring archive; pacman removed it, and a fresh verified edge copy succeeded on the next attempt. Evidence is under `test-runs/oem-iso-evidence/`, including both failed build logs.

ISO built successfully with the edge runtime: `release/omarchy-oem-2026.11.03-x86_64-edge.iso` (6.3 GiB). Both live initramfs files passed the 128 MiB size gate (99,100,666 and 95,395,449 bytes). Now testing the exact ISO in an unprivileged, network-isolated QEMU verifier container with only `/dev/kvm` passed through; target storage is disposable qcow2 files.

Final runtime verification passed on the exact published ISO, offline and without cidata or any key injection: UEFI reached owner setup after 46.8 seconds; BIOS reached it after 41.9 seconds. QMP recorded guest-requested resets. Both targets have encrypted LUKS root partitions (GPT on UEFI, MBR on BIOS). The two-internal-disk test halted at selection, and qemu-img compared both complete disks equal to newly created blank disks. Visual inspection confirmed the existing progress logo and the owner setup greeter. Evidence: `test-runs/oem-iso-evidence/{uefi,bios,multi-uefi}/result.json`, screenshots, QMP events and driver logs.

Verifier infrastructure: the initial minimal QEMU image lacked virtio-vga; adding its display module exposed a QEMU initialization SIGSEGV (core stack includes hw-display-virtio-vga.so). A standard VGA probe worked, so the successful tests used standard VGA. The crash-diagnosis skill was used to inspect the crash facts; no host application/settings were changed. The storage probe handles both GPT and BIOS MBR. All test VM containers exited and were removed; verifier images and local evidence are retained for reproduction.

Published files: `/home/sbull/.local/share/omarchy-iso/public/oem-iso/`, with the original durable copy under `/home/sbull/.local/share/omarchy-iso/oem/d34a53a/`. User service `omarchy-oem-tailshare.service` serves only the publication directory on 127.0.0.1:8765 through the existing Tailscale HTTPS proxy. Direct Tailscale file serving required root, so the existing proxy was used; before/after Tailscale route JSON is identical. The service stays running for downloads (stop with `systemctl --user stop omarchy-oem-tailshare.service`; it is transient and does not survive a host reboot).

ISO: `https://taker.trout-rooster.ts.net/oem-iso/omarchy-oem-2026.11.03-x86_64-edge.iso`
Checksum: `https://taker.trout-rooster.ts.net/oem-iso/omarchy-oem-2026.11.03-x86_64-edge.iso.sha256`
Manifest: `https://taker.trout-rooster.ts.net/oem-iso/manifest.json`
Size: 6,690,965,504 bytes. SHA-256: `75bd3f78391ccfff7f0b76b06594e14c99268514a9c1b252a44240f925635028`. A full streamed HTTPS download matched that hash; the checksum and manifest URLs also returned successfully.

Done criteria are satisfied using the existing personal fork because upstream write access was denied. No merge or production deployment occurred. Physical hardware and aarch64 were not tested; this delivered ISO is x86_64. Firmware should prefer the installed disk over installation media to avoid reinstalling on the next boot.

## Follow-up: regular build and Proxmox regression verification

User requested a build without `--oem` and Proxmox validation, then explicitly directed use of omabot. Regular build command: `./bin/omarchy-iso-make --edge --keep-pkg-cache --no-boot-offer`, in progress. The available configured omabot backend is the legacy Proxmox worker fleet; its fenced key permits worker clones/lifecycle but no new ISO-backed VM creation or ISO attachment. No administrator SSH key is configured, and the ordinary SSH key was denied. The private credential request was stopped after the user directed use of omabot. Use a new omabot-owned worker for further tests; leave existing VMs and the template untouched. Native ISO attachment on the hypervisor is distinct from nested QEMU inside a Proxmox worker, and results must state that boundary.

- [x] Build a regular ISO without the OEM flag and verify it opens the normal interactive wizard without touching the target disk.
- [x] Run the regular interactive install and boot checks using omabot; recheck touchless flow with a Proxmox-style SCSI target.
- [x] Record exact environment and limits, collect screenshots/logs, and destroy only this follow-up's worker.

Follow-up worker: Proxmox VM 9006, name `omabot-oem-iso-regression-9006`, owner `oem-iso-regression`, 8 vCPUs / 16 GiB RAM, created through omabot worker-create and accessed through worker-exec/sync. Initial guest had 40 GiB free and nested KVM enabled. Existing VMs 100, 110, 8999 and 9000–9005 remain untouched. Cleanup owner: primary agent. The regular no-OEM build completed successfully, including both initramfs size gates.

On omabot worker 9006, both transferred images passed SHA-256 verification. The regular ISO stayed at its interactive greeter for 30 seconds with zero keys; qemu-img confirmed its entire 40 GiB target still matched a blank disk. The OEM ISO completed an offline, zero-key UEFI install and auto-rebooted to owner setup on a virtio-SCSI target in 57.0 seconds. Full encrypted interactive install is now running through `bin/omarchy-iso-test --encrypt --install-only --no-preview` using a test-only QEMU adapter for standard VGA, six vCPUs and virtio-SCSI. The initial full-harness launch needed a passwd entry for UID 1000; its verifier container was rerun as its existing root user. No product files were changed.

Follow-up passed: the regular build's real interactive harness completed language/keyboard/account/disk prompts, encrypted installation, the manual reboot prompt, LUKS unlock, console authentication and authenticated SSH. It verified 4096-byte LUKS sectors on the installed root and saved 19 screenshots plus install/timing logs. The regular install screen reported an installation time of 15 seconds. No product code changes were needed. A root-owned serial log could not be copied by rsync, so it was collected separately through omabot worker-exec with sudo.

Regular ISO: `release/omarchy-2026.11.03-x86_64-edge.iso`, SHA-256 `0465c20286e85bae22a368446d2e0d27321677267f6c88b2b6f3f1350ef86dfb`. Touchless SCSI recheck used the original published OEM ISO, SHA-256 unchanged at `75bd3f78391ccfff7f0b76b06594e14c99268514a9c1b252a44240f925635028`, and its installed root was independently confirmed as LUKS-encrypted. Test commands, environment, checksums and structured results are in `test-runs/oem-iso-regression/result.json`; raw logs/screenshots are beside it. The worker was an actual omabot Proxmox guest, with the ISO tests running in nested QEMU/KVM inside it. The nested target used UEFI and virtio-SCSI. Direct Proxmox CD-ROM attachment and the full desktop acceptance suite were not tested.

Cleanup completed: omabot destroyed VM 9006 and both of its logical volumes; its firewall entry was removed. The final VM list matches the initial list, including the existing running VMs and stopped template/workers. No temporary worker remains. The private credential request was not used.
