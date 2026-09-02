#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

dry_run() {
	make -n -C "$root" CONTAINER_ENGINE=docker CONNEXT_VERSION=9.9.9 \
		MY_DOCKER_HUB_ID=tester "$1"
}

assert_contains() {
	output=$1
	expected=$2
	case $output in
	*"$expected"*) ;;
	*)
		printf '%s\n' "missing '$expected' in:" "$output" >&2
		exit 1
		;;
	esac
}

for target in connext-sdk connext-sdk.sample; do
	output=$(dry_run "$target")
	assert_contains "$output" './bin/devrun "docker.io/rticom/connext-sdk:9.9.9" --engine "docker" --name "'"$target"'"'
done

for target in connext-sdk-dev connext-sdk-dev.sample; do
	output=$(dry_run "$target")
	assert_contains "$output" './bin/devrun "docker.io/tester/connext-sdk-dev:9.9.9" --engine "docker" --name "'"$target"'"'
done

output=$(dry_run connext-tools)
assert_contains "$output" './bin/devrun "docker.io/tester/connext-tools:9.9.9" --engine "docker" --name "connext-tools"'

output=$(dry_run xubuntu)
assert_contains "$output" './bin/devrun "docker.io/hectorm/xubuntu:latest"'
assert_contains "$output" '--engine "docker" --name "xubuntu"'

for target in connext-sdk-dev connext-tools; do
	output=$(dry_run "img.$target")
	assert_contains "$output" '-t docker.io/tester/'"$target"':9.9.9'
	output=$(dry_run "push.$target")
	assert_contains "$output" 'image push docker.io/tester/'"$target"':9.9.9'
done

printf '%s\n' 'make dry-run tests passed'
