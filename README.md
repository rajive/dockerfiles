# dockerfiles

Container images and Make targets for development and tools.
`bin/devrun` is the development launcher: it turns an image reference and a
small set of composable profiles into a Podman or Docker invocation.

See [the devrun design](docs/devrun.md) for the rationale and detailed design.

## Requirements

- Lua 5.4 or later and its standard library
- Podman or Docker

## Ad Hoc Development

Run `devrun` from the directory you want to develop in:

```console
./bin/devrun ubuntu:24.04
./bin/devrun docker.io/rajive7400/connext-sdk-dev:7.7.0
./bin/devrun ubuntu:24.04 --engine docker --dry-run
```

An unknown image receives the default `dev` and `identity` profiles. Together
they start an ephemeral interactive Bash shell, mount the exact current
directory at `/workspace`, set it as the working directory, and run as the
host's numeric UID and GID. Files created in the bind-mounted workspace
therefore retain host UID/GID ownership. Podman also uses `--userns=keep-id`
and adds a passwd entry; Docker runs as the numeric user without synthesizing
that entry. Development launches consistently use `devuser` and
`/home/devuser`, regardless of the host account or image. Podman privately
relabels the workspace bind mount for SELinux.

Existing `~/.config/nvim`, `~/.gitconfig`, and `~/.clangd` paths are mounted
read-only. `~/.config/nvim/lazy-lock.json` is mounted afterward as writable,
overriding that nested location so Neovim can update its lock file. Missing
paths are skipped with warnings. The launcher does not search for a repository
root or mount the rest of the host home.

## Command Line

```text
devrun IMAGE [OPTIONS]

-p, --profile NAME   Select a profile; may be repeated
    --name NAME      Override the generated container name
    --engine ENGINE  Select docker or podman
    --dry-run        Print the quoted container command
-h, --help           Show help
```

Examples using explicit profiles:

```console
./bin/devrun ubuntu:24.04 -p dev -p identity
./bin/devrun ubuntu:24.04 -p dev --name scratch
./bin/devrun hectorm/xubuntu:latest -p gui --engine podman --dry-run
```

`--dry-run` prints the fully quoted `run` command and, for `connext`, the
network inspection and conditional creation commands. It does not inspect or
create a network, inspect a container, or launch anything.

Without `--engine`, standalone `devrun` uses the engine in its embedded config
when set, then the first available engine in this order: Podman, Docker. Make
aliases always pass the Make variable `CONTAINER_ENGINE` explicitly; it
defaults to `podman`.

## Profiles And Images

Built-in profiles are:

- `dev`: interactive TTY, `--rm`, `/workspace`, Bash, terminal/timezone
  environment, optional development config, and the shared home volume.
- `identity`: host numeric UID/GID, `USER`, `LOGNAME`, and `HOME`; also
  Podman's keep-id user namespace and passwd entry.
- `connext`: configured bridge network plus an optional read-only RTI license
  at the versioned SDK path. A missing license produces a warning.
- `gui`: detached `--rm` launch using the image's default command, a `2g`
  shared-memory allocation, `/workspace`, and SSH/RDP port publication.

Profile selection has strict precedence:

1. One or more CLI `--profile` values are used in their given order and
   replace all image-mapped profiles and overrides.
2. Otherwise, the first matching image mapping supplies profiles and
   image-specific overrides.
3. Otherwise, `dev` and `identity` are used.

Consequently, `-p dev` alone does not apply numeric identity, while `-p gui`
on a Connext image does not add its network or license policy.

Known mappings are:

| Image                                                              | Profiles                     | Container home policy |
| ------------------------------------------------------------------ | ---------------------------- | --------------------- |
| `docker.io/rticom/connext-sdk:<tag>` or `rticom/connext-sdk:<tag>` | `dev`, `identity`, `connext` | `/home/devuser`       |
| Any image whose repository path ends in `connext-sdk-dev`          | `dev`, `identity`, `connext` | `/home/devuser`       |
| Any image whose repository path ends in `connext-tools`            | `gui`, `connext`             | `/home/user`          |
| `docker.io/hectorm/xubuntu:<tag>` or `hectorm/xubuntu:<tag>`       | `gui`                        | Image default         |

The `dev` profile mounts one named volume, `devrun`, at the canonical container
home `/home/devuser`. Podman requests ownership adjustment for this volume. GUI
mappings do not use the `dev` profile, so they preserve image account policy
and do not mount the shared home volume.

Docker does not have an equivalent to Podman's volume ownership adjustment.
Writable shared-home behavior for Docker remains unverified; use Podman for
development launches that must persist state under `/home/devuser`.

GUI launches return after startup. SSH defaults to `localhost:3322` and RDP to
`localhost:3389`, targeting container ports 3322 and 3389. On successful
startup, `devrun` prints the container name and both endpoints.

## Configuration

Configuration is an embedded Lua table near the top of `bin/devrun`; there is
no external or per-project config file. Edit that table to change defaults,
profiles, mappings, or image overrides.

Optional host-home mounts use compact relative paths:

```lua
optional_home_mounts = {
  readonly = {
    ".bash_logout",
    ".bashrc",
    ".config/kitty/",
    ".config/lazygit/",
    ".config/mise/",
    ".config/nvim/",
    ".config/opencode/",
    ".config/starship.toml",
    ".gitconfig",
    ".gitignore",
    ".gitignore_global",
    ".clangd",
    ".markdownlint.yaml",
    ".profile",
    ".scripts/",
    ".vscode/mcp.json",
    "tools/",
  },
  writable = {
    ".config/nvim/lazy-lock.json",
  },
}
```

Each string is resolved relative to both the host home and the profile's
resolved `container_home`. Absolute, empty, `.`-component, and `..`-component
paths are rejected. Read-only mounts are emitted first, followed by writable
mounts. The nested writable `lazy-lock.json` mount intentionally follows the
read-only `.config/nvim` mount so only that file can be changed. Any source
path that does not exist is skipped with a warning.

The launcher reads:

| Variable                        | Purpose                            | Default                              |
| ------------------------------- | ---------------------------------- | ------------------------------------ |
| `DEVRUN_CONNEXT_VERSION`        | License mount's versioned SDK path | `7.7.0`                              |
| `DEVRUN_NETWORK`                | Connext bridge network             | `my-net`                             |
| `DEVRUN_RTI_LICENSE_FILE`       | Optional RTI license source        | `$HOME/rti/licenses/rti_license.dat` |
| `DEVRUN_TIMEZONE`               | Container timezone                 | `America/Los_Angeles`                |
| `DEVRUN_SSH_HOST_PORT`          | GUI SSH host port                  | `3322`                               |
| `DEVRUN_RDP_HOST_PORT`          | GUI RDP host port                  | `3389`                               |

`TERM` is forwarded by `dev`; `HOME` and the host account identity are used to
construct mounts and identity settings.

The Makefile additionally exposes `CONTAINER_ENGINE`, `MY_DOCKER_HUB_ID`, and
the four image variables `CONNEXT_SDK_IMAGE`, `CONNEXT_SDK_DEV_IMAGE`,
`CONNEXT_TOOLS_IMAGE`, and `XUBUNTU_IMAGE`. It translates its existing
`CONNEXT_VERSION`, `MY_NET`, `RTI_LICENSE_FILE`, and `TZ` settings into the
corresponding `DEVRUN_*` variables for launcher aliases.

## Make Targets

Development aliases are thin `devrun` calls:

```console
make connext-sdk
make connext-sdk-dev
make connext-sdk-dev.feature
make connext-tools
make xubuntu
```

`connext-sdk.<name>` and `connext-sdk-dev.<name>` are also supported; the full
target becomes the container name. The default target is `connext-sdk-dev`.

Build and push this repository's image directories with explicit version tags:

```console
make img.connext-sdk-dev CONNEXT_VERSION=7.7.0
make img.connext-tools CONNEXT_VERSION=7.7.0
make push.connext-sdk-dev CONNEXT_VERSION=7.7.0
make push.connext-tools CONNEXT_VERSION=7.7.0
```

These use
`docker.io/${MY_DOCKER_HUB_ID}/<image-directory>:${CONNEXT_VERSION}`.

## Tests

The tests do not launch containers:

```console
lua tests/devrun_test.lua
sh tests/make_test.sh
luac -p bin/devrun tests/devrun_test.lua
sh -n tests/make_test.sh
```
