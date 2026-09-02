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
  contains(command, "/workspace")
  contains(command, "ubuntu:24.04")
  contains(command, "/bin/bash")
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
