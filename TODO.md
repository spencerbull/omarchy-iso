# OEM ISO

Goal: deliver a zero-touch full-disk OEM ISO and Tailshare download link.

Branch: `oem-iso`, based on `origin/quattro` at `ef1d3897f63f2e0104e461f7bf0d4bb0456168c9`. Checkout: `/home/sbull/.t3/worktrees/omarchy-iso/t3-055bbef0`. Initial checkout was clean.

Allowed: scoped code changes, tests, internal omabot review/fix loop, branch push, ISO build, disposable VM installs, Tailshare publication. Forbidden: production deployment, real disk installation, unrelated user changes, merging into quattro.

- [x] Add opt-in OEM build, retain boot logo/dashboard, automatically select the sole internal disk, use existing encrypted deferred-owner setup and successful-install reboot.
- [x] Run the full VM-free suite and omabot internal review; fix and recheck findings before building.
- [ ] Build x86_64 OEM ISO and verify zero-keystroke installation and first-boot owner setup in a disposable VM.
- [ ] Push `oem-iso`, publish ISO/checksum through Tailshare, report the link.

Disk policy: exactly one writable, unmounted, non-removable, non-hotplug internal disk of at least 32 GiB. Ambiguous or missing targets halt without a prompt or disk writes. Defaults are encrypted storage, US keyboard, English, UTC, hostname `omarchy`; the owner completes setup at first boot.

Review backend: omabot's `review` command. Implementation and verification owner: primary T3 Code agent. No implementation workers. Review evidence and build/VM artifacts will be recorded here.

Verification so far: shell syntax and `git diff --check` pass; `./test/all` passes (387 Python tests, three skips, and all shell tests). Omabot review round 1 identified missing `lsblk --tree`; reproduced with the installed lsblk, fixed, and a regression was proved by removing the fix and observing failure. Full suite passed again after restoring it. Review remains in progress; ISO build has not started.

Review round 1 (Codex XHigh via omabot) checked configuration, credentials/key injection, dashboard success/failure and naming; identified an eMMC ambiguity defect after the earlier mounted-tree and network-device fixes. Added MMC transport/card-type handling, SD exclusion and fail-closed unknown MMC metadata; the eMMC regression fails when its fix is removed. Focused omabot round 2 is reviewing the final selector. Reviewer reports: `/tmp/oem-iso-review/reports/`. Runtime verifier container `omarchy-oem-verifier` is ready; verifier script `/tmp/oem-iso-review/verify-oem.py` sends zero keys and attaches no network or cidata. User confirmed publication through the existing `https://taker.trout-rooster.ts.net` address.

Code gate passed: omabot round 2 (Codex XHigh) reported no actionable findings and cleared the ISO build. The primary agent ran all 392 Python tests (three skips), every shell test, shell syntax and whitespace checks on the final code. The reviewer independently checked mounted ancestry, local-storage filtering, MMC/SD classification and eMMC/NVMe ambiguity; three filesystem-backed MMC tests were blocked in its read-only sandbox, so it verified equivalent cases in memory. Those filesystem-backed tests passed in the primary agent’s full suite.
