# Homebrew tap for binjad

This repository is the third-party Homebrew tap published as `0cyn/homebrew-tap`.

It supports macOS and Linux. It does not contain Binary Ninja or a Binary Ninja license.

## Requirements

- Install the exact Binary Ninja version named by the selected formula.
- Use a Binary Ninja license that permits headless operation.
- Use macOS 14 or newer on macOS.
- Use a current Homebrew-supported Linux system with `systemd` for `brew services`.

## Install the current supported version

The `binjad` alias selects the current supported Binary Ninja build.

```sh
brew install 0cyn/tap/binjad
brew services start 0cyn/tap/binjad
```

## Install an explicit Binary Ninja version

The formula suffix is the required Binary Ninja core version.

```sh
brew install 0cyn/tap/binjad@6.0.10601
brew services start 0cyn/tap/binjad@6.0.10601
```

Only one version can run because all versions use the same listener and service identity.

## Binary Ninja locations

The launcher uses these defaults:

- macOS: `/Applications/Binary Ninja.app`
- Linux: `~/binaryninja`

For another location, set this restart-gated configuration field to an absolute path:

```json
{
  "binary_ninja": {
    "installation_dir": "/absolute/path/to/binaryninja"
  }
}
```

The launcher creates the default configuration before it validates Binary Ninja.

If the default path is unavailable, run `binjad` once, edit the generated configuration, and restart the service.

## Runtime state

The package keeps runtime state outside the Homebrew Cellar.

- macOS: `~/Library/Application Support/binjad`
- Linux: `$XDG_DATA_HOME/binjad`, or `~/.local/share/binjad` when `XDG_DATA_HOME` is unset

Open `http://127.0.0.1:8712/portal` after the service starts.

## Bottle model

Continuous integration builds against Binary Ninja API link stubs. The package never installs those stubs.

The `binjad` launcher has no Binary Ninja dependency. It reads the configuration and executes `libexec/binjad-runtime`.

The launcher supplies the configured core and plugin library paths before the operating-system loader starts the runtime.

The macOS binaries use ad hoc signatures. The tap does not claim Developer ID signing or notarization.

## Maintainer workflow

1. Add or update a versioned formula through a pull request.
2. Let `brew test-bot` build the macOS and Linux bottles.
3. Review all checks and bottle artifacts.
4. Run the `brew pr-pull` workflow with the pull-request number and reviewed head SHA.
5. Move `Aliases/binjad` only after the new version is ready for normal installation.
