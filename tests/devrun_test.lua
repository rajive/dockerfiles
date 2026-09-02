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

local function fake_context(engine)
  return {
    cwd = "/tmp/My Project",
    home = "/home/Test User",
    env = { TERM = "xterm-256color" },
    engine = engine,
    identity = { uid = "1001", gid = "1002", username = "test user" },
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
  list_equal(profiles, { "dev" })
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

test("image mapping overrides profiles", function()
  local resolved = devrun.resolve_launch(
    { image = "rticom/connext-sdk:7.7.0", profiles = {} },
    devrun.config,
    { cwd = "/tmp/project", home = "/home/test", env = {} }
  )

  equal(resolved.container_user, "rtiuser")
  equal(resolved.container_home, "/home/rtiuser")
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
    env = { TERM = "xterm-256color" },
  }
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local command = devrun.build_command(options, launch, context)

  contains(command, "podman")
  contains(command, "run")
  contains(command, "--rm")
  contains(command, "-it")
  contains(command, "/tmp/My Project:/workspace")
  contains(command, "devrun:/home/test")
  contains(command, "/workspace")
  contains(command, "ubuntu:24.04")
  contains(command, "/bin/bash")
end)

test("dev mounts shared home and existing optional configuration read-only", function()
  local options = devrun.parse_args({
    "ubuntu:24.04", "-p", "dev", "--engine", "podman", "--dry-run",
  })
  local context = fake_context("podman")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  local warnings = {}
  devrun.filter_optional_mounts(launch, function(path)
    return path ~= "/home/Test User/.clangd"
  end, function(message)
    warnings[#warnings + 1] = message
  end)
  local command = devrun.build_command(options, launch, context)

  contains(command, "devrun:/home/Test User")
  contains(command, "/home/Test User/.config/nvim:/home/Test User/.config/nvim:ro")
  contains(command, "/home/Test User/.gitconfig:/home/Test User/.gitconfig:ro")
  not_contains(command, "/home/Test User/.clangd:/home/Test User/.clangd:ro")
  equal(#warnings, 1)
  assert(warnings[1]:match("%.clangd"), warnings[1])
end)

test("connext mounts an existing license at the versioned SDK path", function()
  local options = devrun.parse_args({
    "rticom/connext-sdk:7.7.0", "--engine", "podman", "--dry-run",
  })
  local context = fake_context("podman")
  local launch = devrun.resolve_launch(options, devrun.config, context)
  devrun.filter_optional_mounts(launch, function(path)
    return path == devrun.config.defaults.license_file
  end, function() end)
  local command = devrun.build_command(options, launch, context)

  contains(command, devrun.config.defaults.license_file
    .. ":/opt/rti.com/rti_connext_dds-"
    .. devrun.config.defaults.connext_version .. "/rti_license.dat:ro")
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
  contains(podman, "USER=test user")
  contains(podman, "HOME=/home/Test User")

  local docker = identity_command("docker")
  contains(docker, "1001:1002")
  not_contains(docker, "--userns=keep-id")
  not_contains(docker, "--passwd-entry")
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
  equal(#path_checks, 3)
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
    .. "/rti_license.dat:ro"), 1, true), rendered)
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
