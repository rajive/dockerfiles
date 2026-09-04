# devrun Design

## Status

Implemented. The CLI, development, identity, Connext runtime, GUI runtime, Make
integration, workspace ownership, documentation, and acceptance testing are
complete. Deferred work remains listed below.

## Problem

The `connext-sdk`, `connext-sdk-dev`, `connext-tools`, and `xubuntu`
Make targets duplicate container launch configuration.
The duplicated recipes mix image selection with workspace mounts, host identity,
development configuration, networking, licensing, and GUI runtime behavior.

The recipes are also tied to this Makefile.
They cannot conveniently launch an image for ad hoc development from an
arbitrary directory.

## Use Cases

- Start an interactive development shell for an image from the current
  directory.
- Edit and build the mounted directory with Neovim inside the container.
- Launch known GUI development images in detached mode.
- Invoke the same launcher directly or through short Make aliases.
- Customize launch policy by editing a Lua table in the launcher.

## Goals

- Provide one executable named `devrun` under `bin/`.
- Require only Lua 5.4 or later and its standard library.
- Support Podman and Docker.
- Accept an image reference as the required positional argument.
- Compose reusable launch profiles.
- Select profiles automatically for known images.
- Allow explicit CLI profiles to replace automatic profile selection.
- Mount the invocation directory at `/workspace` by default for development.
- Preserve development home state in one shared named volume, `devrun`.
- Keep host configuration mounts explicit and mostly read-only.
- Generate commands deterministically and support inspection with `--dry-run`.

## Non-Goals

- General container lifecycle management.
- A separate user or project configuration file.
- Project configuration discovery or execution.
- Dev Container compatibility.
- Docker Compose replacement.
- Arbitrary command overrides from the CLI in the initial version.
- X11 or Wayland forwarding in the initial version.
- Automatic removal or replacement of an existing named container.

## Repository Placement

`devrun` initially belongs in this repository because its first consumers are
the Make targets and images defined here.
Keeping them together permits an atomic implementation and migration.

The launcher should not depend on the repository layout or read the Makefile.
It should continue to work if copied or symlinked elsewhere.
It may move to a separate repository if it gains unrelated consumers or needs
an independent release lifecycle.

## Command-Line Interface

The command has this form:

```text
devrun IMAGE [OPTIONS]
```

The positional argument is an image reference, not a runtime container name.

Initial options:

```text
-p, --profile NAME    Select a profile; may be repeated
    --name NAME       Override the generated runtime container name
    --engine ENGINE   Select docker or podman
    --dry-run         Print planned actions and the quoted engine command
-h, --help            Show usage
```

Examples:

```console
bin/devrun docker.io/rajive7400/connext-sdk-dev:7.7.0
bin/devrun ubuntu:24.04 -p dev -p identity
bin/devrun ubuntu:24.04 -p dev --engine docker --dry-run
bin/devrun docker.io/rajive7400/connext-tools:7.7.0 --name tools
```

The initial interface does not accept a command after `--` or a shell command
string.
The `dev` profile supplies its configured shell.
The `gui` profile uses the image's default command.

## Configuration Model

Configuration is an ordinary Lua table near the top of `bin/devrun`.
There is no separate configuration file.
The user customizes the launcher by editing this table.

The table contains:

- Environment-aware defaults.
- Default profiles for unknown images.
- Profile functions or tables.
- Ordered exact or pattern-based image mappings.
- Image-specific overrides.

Profile functions receive a context rather than relying on a template language.
The context may expose:

```text
cwd
home
uid
gid
username
host_identity
environment (`env` is an alias)
engine
image
container user and home
top-level configuration
```

Static configuration remains ordinary Lua data.
Functions are used only where a value depends on runtime context.

Profiles use typed fields for common behavior, including:

- Mounts and optional mounts.
- Environment variables.
- Ports.
- Network selection and creation.
- Host numeric-identity mapping.
- Interactive or detached lifecycle.
- Working directory.
- Shared memory size.
- Shell or default image command.

A `run_args` array is available as an escape hatch for engine options not yet
represented by typed fields.
Each element is one engine argument, not a shell command fragment.
Mounts may request private or shared SELinux relabeling; the Podman adapter
renders those requests as `Z` or `z` mount options.

## Profile Selection

Profiles are selected according to these rules:

1. If the CLI supplies one or more `--profile` options, use those profiles in
   CLI order.
2. Otherwise, use the profiles from the first matching image rule.
3. If no image rule matches, use `default_profiles`, initially `dev` and
   `identity`.

Explicit CLI profiles replace automatic image profiles; they do not append to
them.

Selected profiles are applied in order.
Later profiles override scalar values.
List fields append unless the field defines stronger keyed semantics.
For keyed values such as environment variables and mount targets, the later
profile wins.

Image rules are stored in an ordered array so matching does not depend on Lua
table iteration order.
Rules may use exact names or Lua patterns and may provide overrides such as the
container user, container home, shell, ports, and license destination.

Common registry-qualified and unqualified image forms should match
consistently where practical.
Image digests must remain intact.

## Built-In Profiles

### `dev`

The `dev` profile models an ephemeral interactive development shell.
It:

- Runs interactively with a TTY.
- Removes the container after the shell exits.
- Mounts the invocation directory at `/workspace`.
- Sets `/workspace` as the working directory.
- Starts a shell configured by the profile, initially `/bin/bash`.
- Mounts the shared `devrun` volume at `/home/devuser`.
- Passes relevant terminal and timezone environment variables.
- Mounts an explicit allowlist of host development configuration.

Initial allowlisted paths may include Neovim configuration, Git configuration,
and clangd configuration.
They use a compact schema of paths relative to both the host home and the
resolved container home:

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

Absolute paths, empty paths, `.` path components, `..` path components, and
non-string entries are configuration errors. Read-only entries are emitted
before writable entries. The writable nested `lazy-lock.json` mount is an
intentional exception: it follows the read-only `.config/nvim` parent mount so
Neovim can update only its lock file.
Podman applies shared SELinux relabeling to both groups because read-only status
does not change relabel semantics and multiple development containers may use
the same host paths.
The launcher skips a missing optional path and prints a warning rather than
allowing the container engine to create a directory in its place.

The profile does not mount the entire host home or `~/.config`.

### `identity`

The `identity` profile maps the host user's numeric identity into compatible
images. It is selected by default for unknown development images but can be
omitted explicitly because arbitrary images may require their declared user.
Internally, the profile requests `map_host_identity`; resolved host account
data is exposed separately as `host_identity` in the profile context.

Development launches use the canonical account `devuser` and home
`/home/devuser`, independent of the host account and image. The numeric UID and
GID still come from the host so workspace files retain host ownership. GUI
profiles preserve the image's account policy because they omit `identity`.

It may configure:

- Host UID and GID.
- User, logname, and home environment variables.
- Podman's `--userns=keep-id` behavior.
- A passwd entry where supported and needed.
- The closest safe Docker equivalent.

Engine-specific behavior belongs in an adapter rather than in generic profile
merging logic.

### `connext`

The `connext` profile contains RTI-specific runtime policy rather than coupling
it to generic development or GUI behavior.
It:

- Resolves the Connext version from `DEVRUN_CONNEXT_VERSION`, with a table
  fallback.
- Resolves a network from `DEVRUN_NETWORK`, with a table fallback.
- Ensures that the configured bridge network exists before launch.
- Joins the container to that network.
- Optionally mounts the RTI license read-only at the versioned SDK location.

The license source resolves from `DEVRUN_RTI_LICENSE_FILE`, with a table
fallback.
If the file is absent, the launcher warns and continues so another licensing
mechanism can be used.

### `gui`

The `gui` profile models the current remote-desktop image behavior.
It:

- Runs detached and returns after startup.
- Removes the container when it is stopped.
- Uses the image's default command.
- Mounts the invocation directory at `/workspace` and uses it as the working
  directory.
- Configures a shared memory size of `2g` by default.
- Publishes configurable SSH and RDP host ports to container ports 3322 and
  3389.
- Adds any required GUI resources through typed fields or `run_args`.

Default host ports come from environment variables with table fallbacks.
The engine reports port collisions.

The profile does not mount host Firefox profiles, caches, or Snap data.

## Initial Image Mappings

Initial mappings preserve the practical behavior of the existing targets:

| Image | Profiles |
| --- | --- |
| `rticom/connext-sdk:<version>` | `dev`, `identity`, `connext` |
| `*/connext-sdk-dev:<version>` | `dev`, `identity`, `connext` |
| `*/connext-tools:<version>` | `gui`, `connext` |
| `hectorm/xubuntu:<version>` | `gui` |

Mappings may provide image-specific values such as the container home for GUI
images. Development images use the canonical `devuser` account instead.

## Runtime Behavior

### Engine Selection

The engine is selected in this order:

1. `--engine`.
2. The embedded configuration table.
3. Podman, if available.
4. Docker, if available.

The launcher fails clearly if neither engine is available.

### Workspace

For development, the exact invocation directory is mounted at `/workspace`.
The launcher does not search for a Git repository root.
This supports ad hoc work in arbitrary directories and predictable behavior in
subdirectories.
The workspace remains at `/workspace` rather than beneath `/home/devuser`.
This keeps the host bind mount separate from the persistent home volume,
avoids nested mounts, and distinguishes project files from persistent
container state and selected host configuration.

### Persistent Home

Development images share one named volume:

```text
devrun
```

The volume is mounted at the canonical development home `/home/devuser`.
Sharing it preserves Neovim plugins, caches, and shell state across ephemeral
launches and image upgrades without creating per-host or per-image home
directories.
Podman adjusts ownership of this named volume for the active mapped user. This
does not alter ownership of the bind-mounted workspace. It also applies shared
SELinux relabeling so multiple development containers can use the volume.
Docker shared-home ownership requires runtime verification and an explicit
initialization policy before writable persistent-home behavior can be
guaranteed for a host-mapped numeric user.

This intentionally assumes compatible home contents across mapped development
images.
An image mapping may disable or override the volume if that assumption does not
hold.

### Container Naming

Unless `--name` is supplied, the runtime name is derived from the current
directory basename and image repository basename.
The result is lowercased, sanitized for container-engine naming rules, stripped
of repeated separators, and limited to a safe length.

For example, launching `rajive7400/connext-sdk-dev:7.7.0` from a directory named
`shapes` produces a name similar to:

```text
shapes-connext-sdk-dev
```

If that name already exists, the launcher fails with guidance.
It never stops, removes, or replaces an existing container implicitly.

## Docker and Podman Compatibility

The launcher builds a common runtime model and renders it through a small
engine-specific adapter.
The adapter handles differences such as:

- Host identity and user namespaces.
- Passwd entry support.
- SELinux relabeling and volume ownership options.
- Engine command discovery.

Profiles should express intent rather than embed Podman behavior in otherwise
portable fields.
Unsupported combinations should produce clear errors or warnings instead of
silently changing security or ownership behavior.

## Security

The launcher minimizes host exposure by using explicit mounts instead of
mounting all of the host home or configuration directory.
Sensitive host configuration is read-only by default.

The standard library in Lua 5.4 and later has no portable argument-vector
process API.
The launcher therefore:

- Constructs commands internally as argument arrays.
- Quotes every argument with a tested POSIX single-quote encoder.
- Rejects NUL bytes and embedded newlines.
- Never treats configuration values as pre-quoted shell fragments.
- Treats each `run_args` entry as exactly one argument.
- Calls `os.execute` only after all arguments are validated and quoted.

`--dry-run` prints the same quoted command representation that execution uses.

## Make Integration

Make remains a convenient source of short image aliases.
It does not duplicate profile selection or runtime policy.

The four overlapping targets become thin calls similar to:

```make
CONNEXT_SDK_IMAGE ?= docker.io/rticom/connext-sdk:${CONNEXT_VERSION}
CONNEXT_SDK_DEV_IMAGE ?= docker.io/${MY_DOCKER_HUB_ID}/connext-sdk-dev:${CONNEXT_VERSION}
CONNEXT_TOOLS_IMAGE ?= docker.io/${MY_DOCKER_HUB_ID}/connext-tools:${CONNEXT_VERSION}
XUBUNTU_IMAGE ?= docker.io/hectorm/xubuntu:latest

connext-sdk:
	./bin/devrun ${CONNEXT_SDK_IMAGE} --engine ${CONTAINER_ENGINE} --name "$@"

connext-sdk-dev:
	./bin/devrun ${CONNEXT_SDK_DEV_IMAGE} --engine ${CONTAINER_ENGINE} --name "$@"

connext-tools:
	./bin/devrun ${CONNEXT_TOOLS_IMAGE} --engine ${CONTAINER_ENGINE} --name "$@"

xubuntu:
	./bin/devrun ${XUBUNTU_IMAGE} --engine ${CONTAINER_ENGINE} --name "$@"
```

Existing pattern targets such as `connext-sdk-dev.foo` are preserved and pass
the full Make target as `--name`.

Image build and push targets must produce the same explicit version tags that
these aliases launch.

## Testing

Tests use Lua 5.4 or later and no external test framework.
They should cover:

- CLI parsing and validation.
- Profile selection precedence.
- Deterministic profile merging.
- Exact and pattern image matching.
- Image mapping overrides.
- Container-name sanitization.
- POSIX argument quoting and rejected input.
- Optional missing mount handling.
- Docker and Podman argument differences.
- Workspace and shared-home mounts.
- Detached GUI and interactive development behavior.

Dry runs for both engines verify representative commands without pulling RTI
images or requiring an RTI license.

## Deferred Work

- Stop, remove, inspect, or exec lifecycle subcommands.
- Arbitrary CLI command overrides.
- External user or project configuration files.
- Project-root discovery.
- Trust handling for executable project configuration.
- Additional GUI modes such as X11 or Wayland forwarding.
- Automatic host-port allocation.
- Docker named-volume ownership initialization and integration testing.
- Packaging or independent releases.
- Extraction into a separate repository.
