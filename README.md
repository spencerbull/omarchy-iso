# Omarchy ISO

The Omarchy ISO streamlines [the installation of Omarchy](https://learn.omacom.io/2/the-omarchy-manual/50/getting-started). It includes the Omarchy Configurator as a front-end to archinstall and automatically launches the [Omarchy Installer](https://github.com/basecamp/omarchy) after base arch has been setup.

## Downloading the latest ISO

See the ISO link on [omarchy.org](https://omarchy.org).

## Creating the ISO

Run `./bin/omarchy-iso-make` and the output goes into `./release`. You can build from your local $OMARCHY_PATH for testing by using `--local-source` or from a checkout of the dev branch (instead of master) by using `--dev`.

### Environment Variables

Copy `.envrc.template` to `.envrc` and uncomment the variables you want to override. [direnv](https://direnv.net) will pick them up automatically, or `source .envrc` manually.

#### Omarchy installer

- `OMARCHY_INSTALLER_REPO` - GitHub repository for the installer (default: `basecamp/omarchy`)
- `OMARCHY_INSTALLER_REF` - Git ref (branch/tag) for the installer (default: `master`)
- `OMARCHY_MIRROR` - Mirror tier: `stable`, `edge`, or `rc` (default: `stable`)
- `OMARCHY_PATH` - Local path to an Omarchy checkout, used with `--local-source`

```bash
OMARCHY_INSTALLER_REPO="myuser/omarchy-fork" OMARCHY_INSTALLER_REF="some-feature" ./bin/omarchy-iso-make
```

#### Custom Linux kernel

- `LINUX_KERNEL_BRANCH` - AUR linux-mainline branch/tag to build (default: `v7.0-rc4`)

### Building with a custom Linux kernel

Use `--build-kernel` to compile the kernel from the AUR `linux-mainline` PKGBUILD with custom config options and build the ISO in one step (takes 30-90+ min the first time):

```bash
./bin/omarchy-iso-make --build-kernel --no-t2
```

The compiled kernel package is cached in `release/kernels/`. On subsequent ISO builds, use `--custom-kernel` to reuse the cached package without recompiling:

```bash
./bin/omarchy-iso-make --custom-kernel --no-t2
```

You can also run the kernel build step independently:

```bash
./bin/omarchy-iso-build-kernel
```

Kernel config overrides are stored as fragment files in `configs/kernel/`. Each `*.config` file is parsed and applied via `scripts/config` before the kernel build. To add new hardware-specific config options, create a new fragment file in that directory.

Use `--no-t2` to skip the T2 Mac kernel entirely (useful for non-T2 builds). The output ISO will be named with the kernel version appended, e.g. `omarchy-x86_64-master-linux-mainline-v7.0-rc4.iso`.

## Testing the ISO

Run `./bin/omarchy-iso-boot [release/omarchy.iso]`.

## Signing the ISO

Run `./bin/omarchy-iso-sign [gpg-user] [release/omarchy.iso]`.

## Uploading the ISO

Run `./bin/omarchy-iso-upload [release/omarchy.iso]`. This requires you've configured rclone (use `rclone config`).

## Full release of the ISO

Run `./bin/omarchy-iso-release` to create, test, sign, and upload the ISO in one flow.
