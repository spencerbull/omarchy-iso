# OEM bundle: branding, agreement and setup scripts

Goal: an OEM ISO (`omarchy-iso-make --oem`) can be built with the OEM's own config (name, logo, tagline, colour, an optional agreement to accept) and a list of setup scripts; the install lays them down, first-boot owner setup opens on the OEM's branding and asks for the agreement as its last question; validated end to end in a VM with screenshots and a recording; one PR per repository, cross-referenced.

Branches: omarchy-iso `t3/oem-bom-eula-scripts` (this worktree), on top of `fork/oem-first-boot-ux` (the unmerged OEM commits, themselves on `origin/quattro` bb1e77c); omarchy `oem-bom-eula` at `/home/sbull/.t3/worktrees/omarchy/oem-bom-eula` from `origin/quattro` 6baca275b. Allowed: code and tests in both, ISO builds, disposable VMs, pushing branches, opening the two PRs. Not allowed without asking: merging, real disks, production deploys.

Where it is decided: the bundle is checked by `builder/oem-bundle.py` when `bin/omarchy-iso-make` starts and rides in the live image at `/usr/share/omarchy-iso/oem`; the orchestrator lays `oem.json`, `logo.txt` and `eula.txt` down in the target's `/etc/omarchy/oem` (`stage_provisioning_state`) and runs the scripts in the new system as the phase "Running OEM setup", before the boot checks and the factory snapshot. In omarchy, `install/provisioning/oem.sh` reads the bundle and draws the agreement for `bin/omarchy-provision-owner`, and `install/provisioning/console-font.py` draws a logo's braille dots into the console font.

Decisions, the first five made without asking and the last two asked for mid-way:

1. Delivery is build flags (`--oem-config FILE`, `--oem-script FILE`, repeatable), baked into the ISO, and only with `--oem`. A cidata drive does not carry a bundle.
2. Scripts run at install time, as root in the new system, not at the owner's first boot: a failure stops the install at the factory, and what they change is in the factory snapshot.
3. Branding is text: first boot runs on the Linux console (512-glyph Terminus, sixteen colours), so a logo is art of at most 81x12 and the build refuses anything the console cannot be made to draw. No SVG or bitmap there; `chafa` converts one, and the README gives the commands.
4. The agreement is asked after the review and before anything is created; declining leaves the machine as shipped and offers to shut down. Acceptance is recorded in `/var/lib/omarchy/oem/eula-accepted.json`.
5. The agreement is shown in the one language the OEM wrote it in.
6. Asked for: the OEM's logo heads only the greeter and the agreement; the steps between are under Omarchy's.
7. Asked for: a logo in braille dots, as the XPS screensaver on saber is drawn. The console font has none, so the runtime's font tool draws the patterns a logo uses into glyphs the screen's text leaves free, for as long as a branded screen is up.

Plan:

- [x] Read both ends; found the `--oem` work on `fork/oem-first-boot-ux` and based this on it.
- [x] omarchy: `oem.sh` (bundle loader, agreement screen), wiring in `omarchy-provision-owner`, English strings, tests.
- [x] omarchy-iso: `builder/oem-bundle.py`, build flags, live-image staging, orchestrator staging and script phase, dashboard band, harness `--oem-config`, tests, README, sample bundle in `test/unit/fixtures/oem/`.
- [x] Mutation checks: every behaviour the tests claim was broken on purpose in a scratch copy and seen to fail; gaps found that way were closed.
- [x] VM runs with the sample bundle: zero-touch install, first boot, agreement (read on, Ctrl+C and back, decline and back, accept), bundle and record compared on the installed system, both scripts' effects read back over SSH.
- [x] Review round 1 (Codex xhigh, one task per repository). omarchy: three of four findings taken (a logo opening with dashes read by gum as an option; Ctrl+C between the agreement's screens ending setup; the key reader only ever stubbed in tests), one rejected (layout on consoles under about 12 rows, which no Linux console mode is). omarchy-iso: five fixed (validation not seeing a script remove the agreement; staging merging into an existing bundle; a script named like an option skipping its syntax check; a config path opening with a dash; the harness accepting a record for other terms), two already fixed by then.
- [x] Brand placement and braille-dot logos (decisions 6 and 7), with an XPS bundle kept outside the repository.
- [x] Review round 2 on that delta (Codex xhigh): three findings, all fixed (the art font outliving the greeter when setup fails to start; a resize showing the dots as other characters for a moment; blank braille cells not treated as spaces by the validator). The two greeter fixes have no test: the greeter has no seam for one.
- [x] Final VM run on the ISO built from the reviewed heads: harness exit 0, the bundle and the record compared on the installed system, the script's effects read back over SSH.
- [x] PRs, cross-referenced: omarchy https://github.com/omacom/omarchy/pull/18841 (branch `oem-branding-and-agreement`, one commit on quattro) and omarchy-iso https://github.com/spencerbull/omarchy-iso/pull/2 (branch `oem-bundle` against `oem-first-boot-ux`, on the fork because that base is not upstream).
- [x] Asked for on 2026-11-13, after the user ran the XPS ISO in QEMU: the OEM ISO work opened against omacom/omarchy-iso. Two stacked PRs from branches on omacom/omarchy-iso, rebuilt from the tested heads without this ledger (it names local hosts and paths, and upstream has no `TODO.md`): https://github.com/omacom/omarchy-iso/pull/436 (`oem-zero-touch-iso` on quattro: the `--oem` build, the harness, the shared console font; three commits, tree equal to `fork/oem-first-boot-ux` 9d7f8db but for this file) and https://github.com/omacom/omarchy-iso/pull/437 (`oem-bundle` on `oem-zero-touch-iso`; tree equal to 7afa5a4 but for this file). The first commit's README correction (`372fe10`) is folded into it and its author is the user, with Codex in the trailer as before. The fork's PR 2 is superseded by 437 and left open: closing it is the user's call.
- [x] The omarchy PR's `test` check had failed: `luks-rekey-journal-test.sh` lifts `run_setup` and `run_provisioning` out of `omarchy-provision-owner` and stubs the steps around the re-key, and with no stub for the new `eula_form` the attempt loop went back to the keyboard step for ever (CI gave up at 1500 s). Stubbed there with the other forms, and `record_eula` with the other account steps.
- [x] Greptile on the upstream PRs: nothing on 436 or on 18841's new head; one finding on 437, taken (a setup script that rewrote the agreement passed the check that it was still there; the laid-down files are now compared with the ISO's, `d03ad24` upstream and `0d733da` here, the test shown failing without the comparison). Not rerun in a VM: no sample script touches `/etc/omarchy/oem`.
- [x] Asked for in review of 436: the harness's `--record` and `--resolution` are not to go upstream, only the OEM flow. Both are out of the harness commit itself (recorder, its monitor socket, ffmpeg, the display-size option, their tests and README lines), the stack replayed on top and force-pushed with a lease: 436 is now `e610e0d`, 437 `b6efaa3`, and this branch's tree is 437's plus this file. The recorder remains in this branch's history up to `441a493` (and on `fork/oem-first-boot-ux`) for when a recording is wanted again.
- [x] Greptile on 436's new head, P1, taken: `omarchy-iso-release --no-make` after an OEM build would have published it as the release, since its name ends as an ordinary build's does. The release now takes only a build named by its date (`c325042` on 436, merged into 437 as `ee8a301`); the test was shown failing with the old selector.
- [x] VM run of the harness without the recorder, on the XPS ISO (built before these last installer changes): exit 0, bundle and record verified, 23 screenshots, no recording. Run directory `test-runs/omarchy-oem-xps-final-encrypted-provision/runs/20261114-032938`.
- [x] CI on 436 and 437 failed `x86_64: default` and `encrypted` in the `factory-reset` scenario ("Timed out driving the first-boot form"), as quattro's own scheduled run 43522446677 does at the same base: that scenario's form driver did not know the language step omacom/omarchy#18783 added. Taught it (`a94827f` on 436, merged into 437 as `1a8a0b0`). Not run here: the scenario needs a full interactive-ISO install and reset; the PRs' own CI is the check.
- [x] 436 merged by the user on 2026-11-14 (squashed, `176f540` on quattro; quattro's tree is 436's head `a94827f` exactly). 437 followed it: quattro merged into `oem-bundle` (`f89538e`, tree unchanged) and its base moved to quattro, where it shows the bundle alone (20 files).
- [x] omacom/omarchy#18841 merged by the user on 2026-11-14. 437 on quattro at `f89538e`: install test 23 of 23, unit and Greptile pass, mergeable.
- [ ] Human gates: merging 437; closing the fork's PR 2; deleting the merged `oem-zero-touch-iso` branch on omacom/omarchy-iso.


Not run: a factory reset on an OEM install, aarch64, physical hardware, a resolution other than 1280x800, a first boot in a language other than English, and a plain `--oem` ISO with no bundle after the last change to the greeter.

Workers (T3 delegated tasks, Codex gpt-6.1-sol at xhigh, read-only, none left running, nothing to clean up):

- `Review: OEM branding and agreement in first-boot setup (omarchy)`, task `5f83608b`. Done; findings above.
- `Review: OEM bundle build flags, installer phases and harness (omarchy-iso)`, task `ecc6f9e8`. Done; findings above.
- `Review: braille-dot OEM logos and brand placement (omarchy + omarchy-iso delta)`, task `e41fafb5`. Done; findings above.

Evidence: `~/.local/share/omarchy-iso/oem-bom-eula-evidence/` holds `xps-final-1280x800/` (the run on the heads in the PRs: the XPS dot logo, brand on the greeter and agreement only, with screenshots, recording, harness log, the script's effects and the ISO's checksum), `final-1280x800/` (the sample Acme bundle with the brand on every screen, before decisions 6 and 7), `xps-bundle/` (the XPS bundle) and `xps-logo-rendering-options.png` (the dot renderings compared). ISOs are hard-linked under `test-runs/isos/`.

Local tooling, as before: `~/.local/share/omarchy-iso/qemu-test/run <checkout> <harness args>` runs the harness in a container; it mounts only the checkout's parent, so a bundle given to `--oem-config` has to be inside the worktree. `grep` in this machine's interactive shell is a wrapper function: use `command grep` when checking grep's own behaviour.

# OEM first-boot UX parity

Goal: the first boot of an OEM install (the owner's language, keyboard, account) looks and behaves like the ISO installer, with a one-command QEMU flow that installs an OEM ISO and drives first boot, with screenshots and a recording.

Branches: omarchy-iso `t3/oem-first-boot-ux` (this worktree, the OEM commits rebased onto `origin/quattro` bb1e77c); omarchy `oem-first-boot-ux` at `/home/sbull/.t3/worktrees/omarchy/oem-first-boot-ux` from `origin/quattro` 60cb9bf30. Allowed: code and tests in both, ISO builds, disposable VMs, pushing branches, a PR on omarchy under the user's account. Not allowed without asking: merging, real disks, production deploys.

Where it is decided: every first-boot screen is `bin/omarchy-provision-owner` in omarchy, on top of `install/provisioning/setup-form.sh` (prompts) and `progress-icon.sh` (progress), both vendored into the ISO by `builder/build-iso.sh`. The installer side is `configs/airootfs/root/configurator`, `usr/share/omarchy-iso/i18n.sh` and `console-font.py`.

Gaps found (baseline evidence under `test-runs/omarchy-oem-baseline-*`):

1. Font: installer sets patched Terminus (16 or 32 px); first boot picked among kbd's default8x16, sun12x22, latarcyrheb-sun32.
2. gum key hints ("enter submit", "navigate") show at first boot; the installer turns them off in `.automated_script.sh`.
3. Prompt and selection colours differ (purple in the installer, blue/red at first boot): cause not yet pinned, suspect the colour profile gum detects under the systemd unit.
4. No language step at first boot; the form and the desktop stay English.
5. Step order and review table differ (installer: language, keyboard, timezone, username, password, hostname; review lists language first).
6. First-boot strings are hardcoded English, including progress tips.

Plan:

- [x] Rebase onto quattro; baseline OEM ISO and reference installer ISO built from edge.
- [x] Harness: `bin/omarchy-iso-test --oem`, `--record`, `--resolution WxH`; first-boot driver follows whichever prompt is on screen.
- [x] Baseline run green end to end; "before" screens and recording captured.
- [x] omarchy: shared console font, language picker and review table in `setup-form.sh`, first boot in the installer's order, strings in `cli.json`, language applied through `/etc/omarchy/language`. Commit `Ask at first boot what the installer asks, on the installer's screens` on `oem-first-boot-ux`.
- [x] Colour parity: the installer's login shell sets `COLORTERM=yes` (the live image's zsh setup), so gum sends 24-bit colours and the kernel settles them on the palette's purple; the first-boot unit has none. `setup-form.sh` now defaults it.
- [x] ISO: vendor the runtime's console font when it ships one; OEM flow run from `--local-source` builds at 1280x800 and 2560x1600, the regular installer at both for side-by-side, and a hand-driven German first boot (form in German, `/etc/omarchy/language` and the owner's language `de`, `de_DE.utf8` generated, desktop in German).
- [x] Review round 1: Codex xhigh on both diffs. Omarchy: four findings fixed (locale failure swallowed, stale language on retry, translation without Terminus, font size flipping near the threshold), one judgement call left (a portrait console under ~1300 px wide in the 32 px font wraps the logo, as it does in the installer). ISO: six fixed (timezone heading answered early, recorder reading the capabilities reply as a frame's, a blank OCR ending the progress wait, `--oem --free-space`, tests hiding errexit, stale vendored font file in a reused staging directory), three left as they are (base image name ignores `--oem` and resolution, the runtime font path ignores `OMARCHY_ISO_CONSOLE_FONT`, recording is best effort). Every fix has a test that fails without it.
- [x] Review round 2 on the fixes: five more fixed (two unreadable screendumps read as setup finished, the 900 s cap overrun, a test assertion that hid errexit, a timing-fragile recorder test, a mock process leaked on failure); the font rule coming out a size smaller than the kernel's on a few unusual resolutions (2640x1080) is documented in its comment. Final runs of the reviewed build through the final harness: exit 0.
- [x] PR on omarchy: https://github.com/omacom/omarchy/pull/18783 (branch `first-boot-setup-matches-installer` on omacom/omarchy, authored by spencerbull). Greptile's two findings on the first push (a caller's keyboard preset replaced by the language's; new tests belong in the area's existing file) are fixed in two follow-up commits and it now reports nothing open. A Codex pass on the preset follow-up found one low edge left as it is: with `OMARCHY_FORM_KEYBOARD_DEFAULT` exported empty into the unit, a retry in another language keeps the first language's layout preselected; nothing exports it. Copilot was requested and did not start.
- [x] ISO branch pushed: `oem-first-boot-ux` on spencerbull/omarchy-iso. No upstream PR: it sits on the unmerged OEM commits.
- [ ] Human gates: merge of the omarchy PR (its `test` check was still pending at hand-back); whether and how the OEM commits and this harness work go to omacom/omarchy-iso; installing QEMU on this host for native harness runs.

Test results: omarchy-iso `LC_ALL=C ./test/all` passes (without `LC_ALL=C` this host's locale fails `nightly-test.sh` on sort order, on quattro too). Omarchy `./test/shell`: 421 of 424 files pass; `remote-session-service-test.sh`, `tray-symbolic-icon-test.sh` and `shell-idle-spawn-test.sh` fail on this host on a clean `origin/quattro` checkout as well.

Workers (all T3 delegated tasks, Codex gpt-6.1-sol; none left running except where noted; nothing to clean up):

- `First-boot setup shell tests` (high, task `cf56fb9d`): wrote and repaired tests under omarchy `test/shell.d/`. Done; its tests were rerun and later extended by the orchestrator.
- `Review: Omarchy first-boot setup parity` (xhigh, task `88a95733`): read-only. Done; findings above.
- `Review: ISO harness OEM mode and font vendoring` (xhigh, task `b3b26765`): read-only. Done; findings above.
- `Re-review: fixes after first review (both repos)` (xhigh, task `23af3115`): read-only. Done; findings above.
- `Review: keyboard preset follow-up (Omarchy)` (xhigh, task `a85c627c`): read-only. Done; finding above.

Evidence: `~/.local/share/omarchy-iso/oem-first-boot-ux-evidence/` (a copy of `test-runs/oem-first-boot-ux/evidence/`, which is gitignored) holds before/after/installer screenshots at 1280x800 and 2560x1600, the German run, and the before and after recordings. ISOs in `release/`: `omarchy-oem-baseline` and `omarchy-reference` (edge, unchanged runtime), `omarchy-oem-first-boot-ux` (this branch plus the omarchy PR's head).

Local tooling (not in either repo): `~/.local/share/omarchy-iso/qemu-test/{Dockerfile,run}` builds and runs the `omarchy-iso-qemu-test` image, which carries QEMU for this host (none installed, sudo needs a password). `run <checkout> <harness args>` is `bin/omarchy-iso-test` inside it with host networking. ISO builds take about seven minutes with the warm cache. A clean omarchy-pkgs worktree for `--local-source` is at `/home/sbull/.t3/worktrees/omarchy-pkgs-oem-first-boot-ux`.

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

## RC OEM build request

User requested an RC OEM ISO with correct labeling and a Tailscale download. RC repository metadata identifies runtime/settings `4.5.0rc3-1`; the downloaded runtime matched its repository SHA-256. That runtime has deferred provisioning/setup-form but lacks the shared progress-icon.sh required by newer quattro. An isolated detached build worktree `/tmp/omarchy-oem-rc3-build` uses RC3's own ISO source `origin/release/v4-5-0-from-quattro` at `237b724`, with the reviewed OEM commit `d34a53a` cherry-picked as `444fa6a` and build metadata commit `ffd9c59`. Its RC-era dashboard contains the progress renderer directly. The main `oem-iso` product code is unchanged.

Build inputs: `--oem --rc --keep-pkg-cache --no-boot-offer`, x86_64. Version `4.5.0rc3`, ISO volume label `OMARCHY_OEM_450RC3`, application `Omarchy 4.5.0rc3 OEM Installer`; final filename `omarchy-oem-4.5.0rc3-x86_64.iso`. A task-only docker adapter isolates the host package cache to avoid cross-channel archive conflicts. Tests and focused omabot RC-integration review precede the build; then verify the exact artifact on a fresh omabot Proxmox worker and publish without replacing the edge image. Evidence directory: `test-runs/oem-rc-evidence/`.

- [x] Pass RC-source unit suite and omabot integration review.
- [x] Build genuine RC3 OEM ISO with versioned filename and volume label.
- [x] Verify automatic install/reboot/owner setup through omabot; collect evidence and remove worker.
- [x] Publish RC ISO/checksum/manifest separately and verify the HTTPS download hash.

RC source gate passed: full shell suite and 392 Python tests (three skips); omabot/Codex XHigh reviewed the RC-specific OEM port, inline progress compatibility, RC package selection, encryption/deferred setup, failure/success reboot paths and volume metadata, with no actionable findings. ISO build is in progress from clean detached commit `ffd9c59`.

RC verification worker created through omabot: VM 9006, name `omabot-oem-rc3-verify-9006`, owner `oem-rc3-build`, creation stamp `1793746412`, 8 vCPUs / 16 GiB RAM. This is a fresh clone after the earlier regression worker was destroyed. Primary agent owns cleanup; existing VMs/template remain untouched.

RC ISO built successfully (both live initramfs size gates passed). The initial 18-character disc label was valid ISO9660 but exceeded Joliet's 16-character limit. The final artifact uses `OMARCHY450RC3OEM` in both ISO9660 and Joliet, with filename `omarchy-oem-4.5.0rc3-x86_64.iso`. Native xorriso replay preserved BIOS/UEFI boot structures and the original filesystem UUID timestamps; the exact finalized image is being boot-tested in UEFI and BIOS on the omabot worker. Relabel command/log and verified descriptors are in the evidence directory.

User explicitly requested the link while automated testing continues. The RC ISO, checksum and manifest are now published at `https://taker.trout-rooster.ts.net/oem-rc/omarchy-oem-4.5.0rc3-x86_64.iso`; the manifest marks boot/install tests in progress. HTTPS HEAD and checksum download passed. The edge image remains separately published and unchanged. RC SHA-256: `8eae968faba5288b664444c88747f1d15bc9ad0f27a73d40ed63bbebbdec18ae`.

Final RC verification passed on the finalized, relabeled image: UEFI and BIOS each reached owner setup in 57.1 seconds with zero keys, no cidata and no network. Both used virtio-SCSI in nested KVM on the omabot Proxmox worker; QMP recorded guest-requested resets, and independent header probes confirmed encrypted LUKS roots (GPT/UEFI and MBR/BIOS). This does not claim direct Proxmox ISO attachment or physical hardware testing. Evidence, screenshots, boot events and result JSON were collected under `test-runs/oem-rc-evidence/worker-evidence/`. VM 9006, its two volumes and firewall entry were removed; existing VMs and the template remain unchanged.

The public RC manifest now records passed automated tests. The complete HTTPS download matches SHA-256 `8eae968faba5288b664444c88747f1d15bc9ad0f27a73d40ed63bbebbdec18ae`. Final size is 6,537,871,360 bytes; ISO9660/Joliet labels both read `OMARCHY450RC3OEM`, application id `OMARCHY 4.5.0RC3 OEM INSTALLER`. The existing sharing user service remains running for the user's parallel installation test.

RC ISO: `https://taker.trout-rooster.ts.net/oem-rc/omarchy-oem-4.5.0rc3-x86_64.iso`
RC checksum: `https://taker.trout-rooster.ts.net/oem-rc/omarchy-oem-4.5.0rc3-x86_64.iso.sha256`
RC manifest: `https://taker.trout-rooster.ts.net/oem-rc/manifest.json`
