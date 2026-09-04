local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/[^/]+$") or "."
_G.DEVRUN_TESTING = true
local devrun = dofile(root .. "/bin/devrun")

local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ")
      .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function list_equal(actual, expected, message)
  equal(#actual, #expected, (message or "lists differ") .. " length")
  for index, value in ipairs(expected) do
    equal(actual[index], value, (message or "lists differ") .. " at " .. index)
  end
end

local function contains(values, expected, message)
  for _, value in ipairs(values) do
    if value == expected then
      return
    end
  end
  error((message or "list does not contain value") .. ": " .. expected, 2)
end

local function not_contains(values, unexpected, message)
  for _, value in ipairs(values) do
    if value == unexpected then
      error((message or "list contains unexpected value") .. ": " .. unexpected, 2)
    end
  end
end

local function joined(values)
  return table.concat(values, "")
end

local function index_of(values, expected)
  for index, value in ipairs(values) do
    if value == expected then return index end
  end
  return nil
end

local function fake_context(engine)
  return {
    cwd = "/tmp/My Project",
    home = "/home/Test User",
    env = { TERM = "xterm-256color" },
    engine = engine,
    host_identity = { uid = "1001", gid = "1002", username = "test user" },
  }
end

test("parse required image and repeated profiles", function()
  local options = devrun.parse_args({
    "ubuntu:24.04", "-p", "dev", "--profile", "identity",
    "--engine", "docker", "--name", "sample", "--dry-run",
  })

  equal(options.image, "ubuntu:24.04")
  list_equal(options.profiles, { "dev", "identity" })
  equal(options.engine, "docker")
  equal(options.name, "sample")
  equal(options.dry_run, true)
end)

test("reject missing image", function()
  local ok, err = pcall(devrun.parse_args, { "--dry-run" })
  equal(ok, false)
  assert(tostring(err):match("IMAGE is required"), err)
end)

test("CLI profiles replace image profiles", function()
  local profiles = devrun.select_profiles(
    { image = "docker.io/rajive7400/connext-sdk-dev:7.7.0", profiles = { "gui" } },
    devrun.config
  )
  list_equal(profiles, { "gui" })
end)

test("image profiles precede defaults", function()
  local profiles = devrun.select_profiles(
    { image = "docker.io/rajive7400/connext-sdk-dev:7.7.0", profiles = {} },
    devrun.config
  )
  list_equal(profiles, { "dev", "identity", "connext" })

  profiles = devrun.select_profiles(
    { image = "ubuntu:24.04", profiles = {} },
    devrun.config
  )
  list_equal(profiles, { "dev", "identity" })
end)

test("optional registry prefixes do not change upstream image profiles", function()
  for _, image in ipairs({
    "rticom/connext-sdk:7.7.0",
    "rticom/connext-sdk@sha256:0123456789abcdef",
    "docker.io/rticom/connext-sdk:7.7.0",
    "registry.example:5000/team/rticom/connext-sdk",
  }) do
    local profiles = devrun.select_profiles({ image = image, profiles = {} }, devrun.config)
    list_equal(profiles, { "dev", "identity", "connext" }, image)
  end

  for _, image in ipairs({
    "hectorm/xubuntu:latest",
    "docker.io/hectorm/xubuntu:latest",
    "registry.example:5000/team/hectorm/xubuntu@sha256:0123456789abcdef",
  }) do
    local profiles = devrun.select_profiles({ image = image, profiles = {} }, devrun.config)
    list_equal(profiles, { "gui" }, image)
  end
end)

test("optional registry and namespace prefixes do not change custom image profiles", function()
  for _, image in ipairs({
    "connext-sdk-dev",
    "connext-sdk-dev:7.7.0",
    "rajive7400/connext-sdk-dev@sha256:0123456789abcdef",
    "docker.io/rajive7400/connext-sdk-dev:7.7.0",
    "registry.example:5000/team/project/connext-sdk-dev",
  }) do
    local profiles = devrun.select_profiles({ image = image, profiles = {} }, devrun.config)
    list_equal(profiles, { "dev", "identity", "connext" }, image)
  end

  for _, image in ipairs({
    "connext-tools",
    "connext-tools:7.7.0",
    "rajive7400/connext-tools@sha256:0123456789abcdef",
    "docker.io/rajive7400/connext-tools:7.7.0",
    "registry.example:5000/team/project/connext-tools",
  }) do
    local profiles = devrun.select_profiles({ image = image, profiles = {} }, devrun.config)
    list_equal(profiles, { "gui", "connext" }, image)
  end
end)

test("image suffix rules preserve name boundaries", function()
  for _, image in ipairs({
    "notrticom/connext-sdk:7.7.0",
    "not-rticom/connext-sdk:7.7.0",
    "registry.example:5000/team/not-rticom/connext-sdk:7.7.0",
    "rticom/connext-sdk-extra:7.7.0",
    "nothectorm/xubuntu:latest",
    "not-hectorm/xubuntu:latest",
    "registry.example:5000/team/not-hectorm/xubuntu:latest",
    "hectorm/xubuntu-extra:latest",
    "notconnext-sdk-dev:7.7.0",
    "not-connext-sdk-dev:7.7.0",
    "foo.connext-sdk-dev@sha256:0123456789abcdef",
    "notconnext-tools:7.7.0",
    "foo-connext-tools:7.7.0",
    "registry.example:5000/team/foo.connext-tools",
  }) do
    local profiles = devrun.select_profiles({ image = image, profiles = {} }, devrun.config)
    list_equal(profiles, { "dev", "identity" }, image)
  end
end)

test("later profiles override scalars and append lists", function()
  local config = {
    profiles = {
      first = { workdir = "/one", run_args = { "--first" }, env = { A = "1" } },
      second = { workdir = "/two", run_args = { "--second" }, env = { A = "2", B = "3" } },
    },
  }
  local merged = devrun.resolve_profiles({ "first", "second" }, config, {})

  equal(merged.workdir, "/two")
  list_equal(merged.run_args, { "--first", "--second" })
  equal(merged.env.A, "2")
  equal(merged.env.B, "3")
end)

test("later profile mount replaces the same target", function()
  local config = {
    profiles = {
      first = { mounts = { { source = "/one", target = "/workspace" } } },
      second = { mounts = { { source = "/two", target = "/workspace", readonly = true } } },
    },
  }
  local merged = devrun.resolve_profiles({ "first", "second" }, config, {})

  equal(#merged.mounts, 1)
  equal(merged.mounts[1].source, "/two")
  equal(merged.mounts[1].readonly, true)
end)

test("exact image mappings are supported", function()
  local config = {
    default_profiles = { "dev" },
    profiles = { dev = {}, gui = {} },
    images = { { exact = "example/image:1", profiles = { "gui" } } },
  }
  local profiles = devrun.select_profiles(
    { image = "example/image:1", profiles = {} }, config
  )
  list_equal(profiles, { "gui" })
end)

test("development images use the canonical container account", function()
  local resolved = devrun.resolve_launch(
    { image = "rticom/connext-sdk:7.7.0", profiles = {} },
    devrun.config,
    { cwd = "/tmp/project", home = "/home/test", env = {} }
  )

  equal(resolved.container_user, "devuser")
  equal(resolved.container_home, "/home/devuser")
end)

test("untagged known images retain mapped policy", function()
  local cases = {
    {
      image = "docker.io/rticom/connext-sdk",
      profiles = { "dev", "identity", "connext" },
      container_home = "/home/devuser",
    },
    {
      image = "docker.io/rajive7400/connext-sdk-dev",
      profiles = { "dev", "identity", "connext" },
      container_home = "/home/devuser",
    },
    {
      image = "docker.io/rajive7400/connext-tools",
      profiles = { "gui", "connext" },
      container_home = "/home/user",
    },
    {
      image = "docker.io/hectorm/xubuntu",
      profiles = { "gui" },
    },
  }

  for _, case in ipairs(cases) do
    local resolved = devrun.resolve_launch(
      { image = case.image, profiles = {} },
      devrun.config,
      { cwd = "/tmp/project", home = "/home/test", env = {} }
    )
    list_equal(resolved.profiles, case.profiles, case.image)
    equal(resolved.container_home, case.container_home, case.image)
  end
end)

test("generate safe container name", function()
  equal(
    devrun.container_name("/work/My App", "docker.io/rajive7400/connext-sdk-dev:7.7.0"),
    "my-app-connext-sdk-dev"
  )
end)

test("quote POSIX shell arguments", function()
  equal(devrun.shell_quote("plain"), "'plain'")
  equal(devrun.shell_quote("a'b"), "'a'\"'\"'b'")

  local ok = pcall(devrun.shell_quote, "bad\nvalue")
  equal(ok, false)
end)

test("render minimal dev command", function()
  local options = devrun.parse_args({
    "ubuntu:24.04", "-p", "dev", "--engine", "podman", "--dry-run",
  })
  local context = {
    cwd = "/tmp/My Project",
    home = "/home/test",
    username = "testuser",
    env = { TERM = "xterm-256color" },
    host_identity = { uid = "1001", gid = "1002", username = "testuser" },
  }
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)

  contains(command, "podman")
  contains(command, "run")
  contains(command, "--rm")
  contains(command, "-it")
  contains(command, "/tmp/My Project:/workspace:Z")
  contains(command, "devrun:/home/devuser:U,z")
  not_contains(command, "devrun:/home/devuser:U,Z")
  contains(command, "/workspace")
  contains(command, "ubuntu:24.04")
  contains(command, "/bin/bash")
end)

test("dev expands and renders ordered optional home mounts", function()
  for _, engine in ipairs({ "docker", "podman" }) do
    local options = devrun.parse_args({
      "ubuntu:24.04", "-p", "dev", "--engine", engine, "--dry-run",
    })
    local context = fake_context(engine)
    local launch = devrun.resolve_launch(options, devrun.config, context)
    equal(#launch.optional_mounts, 18)
    equal(launch.optional_mounts[1].source, "/home/Test User/.bash_logout")
    equal(launch.optional_mounts[1].target, "/home/devuser/.bash_logout")
    equal(launch.optional_mounts[1].readonly, true)
    equal(launch.optional_mounts[1].relabel, "shared")
    equal(launch.optional_mounts[18].source,
      "/home/Test User/.config/nvim/lazy-lock.json")
    equal(launch.optional_mounts[18].readonly, false)
    equal(launch.optional_mounts[18].relabel, "shared")

    local warnings = {}
    devrun.filter_optional_mounts(launch, function(path)
      return path ~= "/home/Test User/.clangd"
    end, function(message)
      warnings[#warnings + 1] = message
    end)
    local command = devrun.build_command(options, launch, context)
    local parent = "/home/Test User/.config/nvim/:/home/devuser/.config/nvim/:ro"
    local lock = "/home/Test User/.config/nvim/lazy-lock.json:"
      .. "/home/devuser/.config/nvim/lazy-lock.json"
    if engine == "podman" then
      parent = parent .. ",z"
      lock = lock .. ":z"
    end

    contains(command, parent)
    contains(command, "/home/Test User/.gitconfig:/home/devuser/.gitconfig:ro"
      .. (engine == "podman" and ",z" or ""))
    not_contains(command, "/home/Test User/.clangd:/home/devuser/.clangd:ro"
      .. (engine == "podman" and ",z" or ""))
    contains(command, lock)
    if engine == "podman" then
      not_contains(command, "/home/Test User/.config/nvim/:/home/devuser/.config/nvim/:ro,Z")
      not_contains(command, "/home/Test User/.config/nvim/lazy-lock.json:"
        .. "/home/devuser/.config/nvim/lazy-lock.json:Z")
    end
    assert(index_of(command, parent) < index_of(command, lock), engine)
    equal(#warnings, 1)
    assert(warnings[1]:match("%.clangd"), warnings[1])
  end
end)

test("optional home mounts reject unsafe and malformed paths", function()
  local invalid = {
    { path = "/absolute", message = "non%-empty relative path" },
    { path = "", message = "non%-empty relative path" },
    { path = "config/./file", message = "path components" },
    { path = "config/../secret", message = "path components" },
    { path = 42, message = "relative path string" },
  }
  for _, case in ipairs(invalid) do
    local config = {
      default_profiles = { "test" },
      profiles = { test = { optional_home_mounts = { readonly = { case.path } } } },
    }
    local ok, err = pcall(devrun.resolve_launch,
      { image = "image", profiles = {} }, config,
      { cwd = "/tmp/project", home = "/home/test", env = {} })
    equal(ok, false)
    assert(tostring(err):match("optional_home_mounts%.readonly%[1%]"), tostring(err))
    assert(tostring(err):match(case.message), tostring(err))
  end
end)

test("invalid optional home mounts fail before engine side effects", function()
  local old_profile = devrun.config.profiles.invalidmount
  devrun.config.profiles.invalidmount = {
    optional_home_mounts = { writable = { "../escape" } },
  }
  local execute_calls, capture_calls = 0, 0
  local call_ok, status = pcall(devrun.run, {
    "image", "-p", "invalidmount", "--engine", "docker",
  }, {
    cwd = "/tmp/project",
    stderr = function() end,
    execute = function() execute_calls = execute_calls + 1 end,
    capture = function() capture_calls = capture_calls + 1 end,
  })
  devrun.config.profiles.invalidmount = old_profile

  equal(call_ok, true)
  equal(status, 2)
  equal(execute_calls, 0)
  equal(capture_calls, 0)
end)

test("connext mounts an existing license at the versioned SDK path", function()
  local mount = devrun.config.defaults.license_file
    .. ":/opt/rti.com/rti_connext_dds-"
    .. devrun.config.defaults.connext_version .. "/rti_license.dat:ro"
  for _, engine in ipairs({ "docker", "podman" }) do
    local options = devrun.parse_args({
      "rticom/connext-sdk:7.7.0", "--engine", engine, "--dry-run",
    })
    local context = fake_context(engine)
    local launch = devrun.resolve_launch(options, devrun.config, context)
    devrun.filter_optional_mounts(launch, function(path)
      return path == devrun.config.defaults.license_file
    end, function() end)
    local command = devrun.build_command(options, launch, context)

    contains(command, mount .. (engine == "podman" and ",z" or ""))
    if engine == "docker" then not_contains(command, mount .. ",z") end
  end
end)

test("connext warns and continues when the license is absent", function()
  local options = devrun.parse_args({
    "rticom/connext-sdk:7.7.0", "--engine", "docker", "--dry-run",
  })
  local context = fake_context("docker")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local warnings = {}
  devrun.filter_optional_mounts(launch, function() return false end, function(message)
    warnings[#warnings + 1] = message
  end)
  local command = devrun.build_command(options, launch, context)

  assert(joined(warnings):match("RTI license file does not exist"), joined(warnings))
  not_contains(command, devrun.config.defaults.license_file
    .. ":/opt/rti.com/rti_connext_dds-"
    .. devrun.config.defaults.connext_version .. "/rti_license.dat:ro")
end)

test("connext adds the configured network to the run command", function()
  local options = devrun.parse_args({
    "rticom/connext-sdk:7.7.0", "--engine", "docker", "--dry-run",
  })
  local context = fake_context("docker")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)
  local network_index
  for index, value in ipairs(command) do
    if value == "--network" then network_index = index end
  end

  assert(network_index, "missing --network")
  equal(command[network_index + 1], devrun.config.defaults.network)
end)

test("identity rendering keeps Podman flags out of Docker", function()
  local function identity_command(engine)
    local options = devrun.parse_args({
      "ubuntu:24.04", "-p", "dev", "-p", "identity", "--engine", engine, "--dry-run",
    })
    local context = fake_context(engine)
    local launch = devrun.resolve_launch(options, devrun.config, context)
    return devrun.build_command(options, launch, context)
  end

  local podman = identity_command("podman")
  contains(podman, "1001:1002")
  contains(podman, "--userns=keep-id")
  contains(podman, "--passwd-entry")
  contains(podman, "USER=devuser")
  contains(podman, "LOGNAME=devuser")
  contains(podman, "HOME=/home/devuser")

  local docker = identity_command("docker")
  contains(docker, "1001:1002")
  contains(docker, "devrun:/home/devuser")
  not_contains(docker, "devrun:/home/devuser:U,z")
  not_contains(docker, "--userns=keep-id")
  not_contains(docker, "--passwd-entry")
end)

test("development images share canonical account while GUI preserves image policy", function()
  local rti_options = devrun.parse_args({
    "docker.io/rajive7400/connext-sdk-dev:7.7.0", "--engine", "podman", "--dry-run",
  })
  local rti_context = fake_context("podman")
  local rti_launch = devrun.resolve_launch(rti_options, devrun.config, rti_context)
  local rti_command = devrun.build_command(rti_options, rti_launch, rti_context)

  contains(rti_command, "USER=devuser")
  contains(rti_command, "HOME=/home/devuser")
  contains(rti_command, "devuser:x:1001:1002:devuser:/home/devuser:/bin/bash")

  local gui_options = devrun.parse_args({
    "docker.io/rajive7400/connext-tools:7.7.0", "--engine", "podman", "--dry-run",
  })
  local gui_launch = devrun.resolve_launch(gui_options, devrun.config, fake_context("podman"))
  equal(gui_launch.container_home, "/home/user")
  equal(gui_launch.map_host_identity, nil)
end)

test("GUI rendering is portable and preserves the image default command", function()
  for _, engine in ipairs({ "docker", "podman" }) do
    local image = "hectorm/xubuntu:latest"
    local options = devrun.parse_args({ image, "--engine", engine, "--dry-run" })
    local context = fake_context(engine)
    local launch = devrun.resolve_launch(options, devrun.config, context)
    local command = devrun.build_command(options, launch, context)

    contains(command, "--rm")
    contains(command, "-d")
    not_contains(command, "-it")
    local shm = assert(index_of(command, "--shm-size"), "missing --shm-size")
    equal(command[shm + 1], "2g")
    local workdir = assert(index_of(command, "-w"), "missing GUI workdir")
    equal(command[workdir + 1], "/workspace")
    if engine == "podman" then
      contains(command, "/tmp/My Project:/workspace:Z")
    else
      contains(command, "/tmp/My Project:/workspace")
      not_contains(command, "/tmp/My Project:/workspace:Z")
    end
    contains(command, "3322:3322/tcp")
    contains(command, "3389:3389/tcp")
    contains(command, "TZ=" .. devrun.config.defaults.timezone)
    equal(command[#command], image, "GUI command must end at image")
  end
end)

test("connext-tools composes GUI and Connext behavior", function()
  local options = devrun.parse_args({
    "docker.io/rajive7400/connext-tools:7.7.0", "--engine", "podman", "--dry-run",
  })
  local context = fake_context("podman")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)

  list_equal(launch.profiles, { "gui", "connext" })
  equal(launch.detached, true)
  equal(launch.ensure_network, devrun.config.defaults.network)
  contains(command, "--network")
  contains(command, devrun.config.defaults.network)
  equal(#launch.optional_mounts, 1)
end)

test("xubuntu selects only GUI behavior without Connext or browser mounts", function()
  local options = devrun.parse_args({
    "hectorm/xubuntu:latest", "--engine", "docker", "--dry-run",
  })
  local context = fake_context("docker")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)

  list_equal(launch.profiles, { "gui" })
  equal(launch.ensure_network, nil)
  equal(launch.network, nil)
  equal(launch.optional_mounts, nil)
  not_contains(command, "--network")
  for _, value in ipairs(command) do
    assert(not value:match("mozilla"), value)
    assert(not value:match("firefox"), value)
    assert(not value:match("snap"), value)
  end
end)

test("explicit GUI profile replaces automatic Connext mapping", function()
  local options = devrun.parse_args({
    "docker.io/rajive7400/connext-tools:7.7.0", "-p", "gui",
    "--engine", "docker", "--dry-run",
  })
  local context = fake_context("docker")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)

  list_equal(launch.profiles, { "gui" })
  equal(launch.ensure_network, nil)
  not_contains(command, "--network")
end)

test("GUI uses configured SSH and RDP host ports", function()
  local old_ssh = devrun.config.defaults.ssh_port
  local old_rdp = devrun.config.defaults.rdp_port
  devrun.config.defaults.ssh_port = 22022
  devrun.config.defaults.rdp_port = 23389

  local options = devrun.parse_args({
    "hectorm/xubuntu:latest", "--engine", "docker", "--dry-run",
  })
  local context = fake_context("docker")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)
  devrun.config.defaults.ssh_port = old_ssh
  devrun.config.defaults.rdp_port = old_rdp

  contains(command, "22022:3322/tcp")
  contains(command, "23389:3389/tcp")
end)

test("GUI environment-backed port defaults retain valid integers", function()
  local function expected(name, fallback)
    local value = os.getenv(name)
    if value == nil or value == "" then return fallback end
    if value:match("^%d+$") then return tonumber(value) end
    return value
  end

  equal(devrun.config.defaults.ssh_port, expected("DEVRUN_SSH_HOST_PORT", 3322))
  equal(devrun.config.defaults.rdp_port, expected("DEVRUN_RDP_HOST_PORT", 3389))
end)

test("GUI rejects invalid port configuration", function()
  local invalid = {
    { field = "host", value = "not-a-port", message = "host port" },
    { field = "host", value = 22.5, message = "host port" },
    { field = "host", value = 0, message = "host port" },
    { field = "host", value = 65536, message = "host port" },
    { field = "container", value = "3322", message = "container port" },
  }
  for _, case in ipairs(invalid) do
    local port = { host = 3322, container = 3322, protocol = "tcp" }
    port[case.field] = case.value
    local ok, err = pcall(devrun.validate_launch, { ports = { port } })
    equal(ok, false)
    assert(tostring(err):match(case.message), tostring(err))
    assert(tostring(err):match("integer in 1%.%.65535"), tostring(err))
  end
end)

test("GUI accepts tcp and udp and rejects invalid protocols", function()
  devrun.validate_launch({
    ports = {
      { host = 1001, container = 1002, protocol = "tcp" },
      { host = 1003, container = 1004, protocol = "udp" },
    },
  })
  local ok, err = pcall(devrun.validate_launch, {
    ports = { { host = 1001, container = 1002, protocol = "icmp" } },
  })
  equal(ok, false)
  assert(tostring(err):match("protocol must be tcp or udp"), tostring(err))
end)

test("GUI port rendering keeps metacharacters inert by rejecting them", function()
  local ok, err = pcall(devrun.build_command,
    { image = "image", engine = "docker" },
    { ports = { { host = "3322;$(false)", container = 3322, protocol = "tcp" } } },
    fake_context("docker"))
  equal(ok, false)
  assert(tostring(err):match("host port"), tostring(err))
end)

test("invalid GUI configuration fails before dry-run or execution", function()
  local old_ssh = devrun.config.defaults.ssh_port
  devrun.config.defaults.ssh_port = "bad"
  local output = {}
  local errors = {}
  local side_effects = 0
  local status = devrun.run({
    "hectorm/xubuntu:latest", "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    stdout = function(value) output[#output + 1] = value end,
    stderr = function(value) errors[#errors + 1] = value end,
    execute = function() side_effects = side_effects + 1 end,
  })
  devrun.config.defaults.ssh_port = old_ssh

  equal(status, 2)
  equal(joined(output), "")
  equal(side_effects, 0)
  assert(joined(errors):match("host port must be an integer in 1%.%.65535"), joined(errors))
end)

test("successful detached launch prints connection details", function()
  local output = {}
  local commands = {}
  local status = devrun.run({
    "hectorm/xubuntu:latest", "--engine", "docker", "--name", "desktop",
  }, {
    cwd = "/tmp/project",
    path_exists = function() return false end,
    stdout = function(value) output[#output + 1] = value end,
    stderr = function() end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return true, "exit", 0
    end,
  })

  equal(status, 0)
  local rendered = joined(output)
  assert(rendered:match("Container: desktop"), rendered)
  assert(rendered:match("SSH: localhost:" .. devrun.config.defaults.ssh_port), rendered)
  assert(rendered:match("RDP: localhost:" .. devrun.config.defaults.rdp_port), rendered)
end)

test("failed detached launch prints no connection details", function()
  local output = {}
  local commands = {}
  local status = devrun.run({
    "hectorm/xubuntu:latest", "--engine", "podman", "--name", "desktop",
  }, {
    cwd = "/tmp/project",
    path_exists = function() return false end,
    stdout = function(value) output[#output + 1] = value end,
    stderr = function() end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return nil, "exit", 125
    end,
  })

  equal(status, 125)
  equal(joined(output), "")
end)

test("run executes quoted command and propagates engine status", function()
  local commands = {}
  local status = devrun.run({
    "ubuntu:24.04", "-p", "dev", "--engine", "docker", "--name", "name with spaces",
  }, {
    cwd = "/tmp/Project With Spaces",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function() end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return nil, "exit", 37
    end,
  })

  equal(status, 37)
  assert(commands[1]:match("'docker' 'container' 'inspect' 'name with spaces'"), commands[1])
  assert(commands[2]:match("'/tmp/Project With Spaces:/workspace'"), commands[2])
  assert(commands[2]:match("'name with spaces'"), commands[2])
end)

test("run resolves host identity only for identity profile", function()
  local identity_calls = 0
  local status = devrun.run({
    "ubuntu:24.04", "-p", "dev", "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      identity_calls = identity_calls + 1
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function() end,
    stdout = function() end,
  })

  equal(status, 0)
  equal(identity_calls, 0)
end)

test("custom identity profile resolves host identity", function()
  local identity_calls = 0
  local observed
  local old_identity_profile = devrun.config.profiles.customidentity
  local old_observer_profile = devrun.config.profiles.observeidentity
  devrun.config.profiles.customidentity = { map_host_identity = true }
  devrun.config.profiles.observeidentity = function(ctx)
    observed = { uid = ctx.uid, gid = ctx.gid, username = ctx.username }
    return {}
  end
  local status = devrun.run({
    "ubuntu:24.04", "-p", "dev", "-p", "customidentity", "-p", "observeidentity",
    "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      identity_calls = identity_calls + 1
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stdout = function() end,
    stderr = function() end,
  })
  devrun.config.profiles.customidentity = old_identity_profile
  devrun.config.profiles.observeidentity = old_observer_profile

  equal(status, 0)
  equal(identity_calls, 1)
  equal(observed.uid, "1001")
  equal(observed.gid, "1002")
  equal(observed.username, "tester")
end)

test("profile context exposes direct host identity fields", function()
  local observed
  local old_profile = devrun.config.profiles.observeidentity
  devrun.config.profiles.observeidentity = function(ctx)
    observed = { uid = ctx.uid, gid = ctx.gid, username = ctx.username }
    return { map_host_identity = true }
  end
  local status = devrun.run({
    "ubuntu:24.04", "-p", "identity", "-p", "observeidentity",
    "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    stdout = function() end,
    stderr = function() end,
  })
  devrun.config.profiles.observeidentity = old_profile

  equal(status, 0)
  equal(observed.uid, "1001")
  equal(observed.gid, "1002")
  equal(observed.username, "tester")
end)

test("run refuses to replace an existing named container", function()
  local commands = {}
  local errors = {}
  local status = devrun.run({
    "ubuntu:24.04", "-p", "dev", "--engine", "podman", "--name", "existing",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function(value) errors[#errors + 1] = value end,
    execute = function(command)
      commands[#commands + 1] = command
      return true, "exit", 0
    end,
  })

  equal(status, 2)
  equal(#commands, 1)
  assert(commands[1]:match("container.*inspect"), commands[1])
  assert(table.concat(errors):match("already exists"), table.concat(errors))
  assert(table.concat(errors):match("choose another %-%-name"), table.concat(errors))
end)

test("run checks the generated container name before launch", function()
  local inspected
  local status = devrun.run({
    "ubuntu:24.04", "-p", "dev", "--engine", "docker",
  }, {
    cwd = "/tmp/My Project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function() end,
    execute = function(command)
      inspected = command
      return true, "exit", 0
    end,
  })

  equal(status, 2)
  assert(inspected:match("'my%-project%-ubuntu'"), inspected)
end)

test("connext launch uses an existing network without creating it", function()
  local commands = {}
  local captures = {}
  local network = devrun.config.defaults.network
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "docker",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function() end,
    capture = function(arguments)
      captures[#captures + 1] = arguments
      return 0, "other\n" .. network .. "\n"
    end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return true, "exit", 0
    end,
  })

  equal(status, 0)
  equal(#captures, 1)
  list_equal(captures[1], { "docker", "network", "ls", "--format", "{{.Name}}" })
  equal(#commands, 2)
  assert(commands[2]:match("'docker' 'run'"), commands[2])
end)

test("connext launch creates an absent bridge network before launch", function()
  local commands = {}
  local network = devrun.config.defaults.network
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "podman",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function() end,
    capture = function() return 0, "unrelated\n" end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return true, "exit", 0
    end,
  })

  equal(status, 0)
  equal(#commands, 3)
  equal(commands[2], devrun.render_command({
    "podman", "network", "create", "--driver", "bridge", network,
  }))
  assert(commands[3]:match("'podman' 'run'"), commands[3])
end)

test("connext launch stops when network creation fails", function()
  local commands = {}
  local errors = {}
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "docker",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function(value) errors[#errors + 1] = value end,
    capture = function() return 0, "" end,
    execute = function(command)
      commands[#commands + 1] = command
      if #commands == 1 then return nil, "exit", 1 end
      return nil, "exit", 42
    end,
  })

  equal(status, 1)
  equal(#commands, 2)
  assert(commands[2]:match("network' 'create"), commands[2])
  assert(joined(errors):match("failed to create network"), joined(errors))
  assert(joined(errors):match("exit 42"), joined(errors))
end)

test("connext launch treats network listing failure as operational failure", function()
  local commands = {}
  local errors = {}
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "docker",
  }, {
    cwd = "/tmp/project",
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    path_exists = function() return false end,
    stderr = function(value) errors[#errors + 1] = value end,
    capture = function() return 13, "permission denied\n" end,
    execute = function(command)
      commands[#commands + 1] = command
      return nil, "exit", 1
    end,
  })

  equal(status, 1)
  equal(#commands, 1)
  assert(joined(errors):match("failed to inspect networks"), joined(errors))
  assert(joined(errors):match("permission denied"), joined(errors))
end)

test("connext dry-run prints prerequisites without external side effects", function()
  local output = {}
  local side_effects = 0
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    path_exists = function() return false end,
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    stdout = function(value) output[#output + 1] = value end,
    stderr = function() end,
    capture = function() side_effects = side_effects + 1 end,
    execute = function() side_effects = side_effects + 1 end,
  })

  equal(status, 0)
  equal(side_effects, 0)
  local rendered = joined(output)
  assert(rendered:match("# inspect: 'docker' 'network' 'ls'"), rendered)
  assert(rendered:match("# if absent: 'docker' 'network' 'create' '%-%-driver' 'bridge'"), rendered)
  assert(rendered:match("'docker' 'run'.*'%-%-network'"), rendered)
end)

test("invalid connext launch command fails before external side effects", function()
  local errors = {}
  local execute_calls = 0
  local capture_calls = 0
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0\nbad", "--engine", "docker",
  }, {
    cwd = "/tmp/project",
    path_exists = function() return false end,
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    stderr = function(value) errors[#errors + 1] = value end,
    capture = function() capture_calls = capture_calls + 1 end,
    execute = function() execute_calls = execute_calls + 1 end,
  })

  equal(status, 2)
  equal(execute_calls, 0)
  equal(capture_calls, 0)
  assert(joined(errors):match("^devrun: "), joined(errors))
  assert(joined(errors):match("command arguments may not contain NUL or newlines"), joined(errors))
end)

test("explicit generic dev replaces Connext work", function()
  local output = {}
  local path_checks = {}
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "-p", "dev", "--engine", "docker", "--dry-run",
  }, {
    cwd = "/tmp/project",
    path_exists = function(path)
      path_checks[#path_checks + 1] = path
      return false
    end,
    stdout = function(value) output[#output + 1] = value end,
    stderr = function() end,
    capture = function() error("network capture must not run") end,
    execute = function() error("execute must not run") end,
  })

  equal(status, 0)
  equal(#path_checks, 18)
  local rendered = joined(output)
  assert(not rendered:match("network"), rendered)
  assert(not rendered:match("rti_license"), rendered)
end)

test("network and license shell metacharacters remain quoted", function()
  local old_network = devrun.config.defaults.network
  local old_license = devrun.config.defaults.license_file
  devrun.config.defaults.network = "team net;$(false)'x"
  devrun.config.defaults.license_file = "/tmp/license path;$(false)'x.dat"

  local output = {}
  local status = devrun.run({
    "rticom/connext-sdk:7.7.0", "--engine", "podman", "--dry-run",
  }, {
    cwd = "/tmp/project",
    path_exists = function(path) return path == devrun.config.defaults.license_file end,
    host_identity = function()
      return { uid = "1001", gid = "1002", username = "tester" }
    end,
    stdout = function(value) output[#output + 1] = value end,
    stderr = function() end,
  })
  devrun.config.defaults.network = old_network
  devrun.config.defaults.license_file = old_license

  equal(status, 0)
  local rendered = joined(output)
  assert(rendered:find(devrun.shell_quote("team net;$(false)'x"), 1, true), rendered)
  assert(rendered:find(devrun.shell_quote("/tmp/license path;$(false)'x.dat:"
    .. "/opt/rti.com/rti_connext_dds-" .. devrun.config.defaults.connext_version
    .. "/rti_license.dat:ro,z"), 1, true), rendered)
end)

local failures = 0
for _, item in ipairs(tests) do
  local ok, err = pcall(item.fn)
  if ok then
    io.stdout:write("ok - ", item.name, "\n")
  else
    failures = failures + 1
    io.stderr:write("not ok - ", item.name, "\n", tostring(err), "\n")
  end
end

io.stdout:write(string.format("%d tests, %d failures\n", #tests, failures))
os.exit(failures == 0 and 0 or 1)
