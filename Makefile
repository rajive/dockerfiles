# Command-style targets.
.PHONY: default FORCE ensure-network \
	cds.svc cds.pub cds.sub \
	col.svc \
	rte.svc \
	rec.svc rpl.svc mem.per.svc dsk.per.svc per.sub \
	web.svc \
	prf.pub.thr prf.pub.lat prf.sub \
	spy pub sub \
	connext-sdk-dev \
	xubuntu connext-tools \
	prune prune_all

# User configuration: review and update these for your environment.
CONTAINER_ENGINE ?= podman
MY_DOCKER_HUB_ID ?= rajive7400
RTI_LICENSE_FILE ?= ~/rti/licenses/rti_license.dat
CONNEXT_VERSION ?= 7.7.0
DOMAIN ?= 0
MY_NET ?= my-net

# Internal derived paths: these are computed from the user configuration above.
CONNEXT_HOME := /opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}
CONNEXT_WORKSPACE := /home/rtiuser/rti_workspace/${CONNEXT_VERSION}
RTI_LICENSE_MOUNT := ${RTI_LICENSE_FILE}:${CONNEXT_HOME}/rti_license.dat

# Collector Service currently publishes amd64 images only.
COLLECTOR_PLATFORM := linux/amd64

default: connext-sdk-dev

FORCE:

# Network setup
# Ensure the named bridge network exists before starting containers on it.
ensure-network:
	@test -n "${MY_NET}" || { echo "MY_NET must not be empty"; exit 1; }
	@${CONTAINER_ENGINE} network inspect ${MY_NET} >/dev/null 2>&1 || \
		${CONTAINER_ENGINE} network create -d bridge ${MY_NET}

# Cloud Discovery Service
# must be the first container on the network
cds.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=$@ \
		rticom/cloud-discovery-service \
		-cfgName defaultWAN
cds.pub cds.pub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

cds.sub cds.sub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-ping \
		-subscriber \
		-domain ${DOMAIN}

# Routing Service
rte.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=$@ \
		rticom/routing-service \
		-cfgName DomainBridgingLAN

# Record and Replay
rec.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--mount type=volume,source=recording_service_database,target=${CONNEXT_WORKSPACE}/database \
		--name=$@ \
		rticom/recording-service \
		-cfgName default

rpl.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--mount type=volume,source=recording_service_database,target=${CONNEXT_WORKSPACE}/database \
		--name=$@ \
		rticom/replay-service \
		-cfgName default

# Persistence Service (fails)
mem.per.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=$@ \
		rticom/persistence-service \
		-cfgName default

dsk.per.svc: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--mount type=volume,source=persistence_service_database,target=${CONNEXT_WORKSPACE}/database \
		--name=$@ \
		rticom/persistence-service \
		-cfgName defaultDisk

per.sub per.sub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-subscriber \
		-domain ${DOMAIN}

# Web Integration Service
web.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network host \
		-v ${RTI_LICENSE_MOUNT} \
		--name=$@ \
		rticom/web-integration-service \
		-cfgName shapesDemoTutorial \
		-documentRoot ${CONNEXT_WORKSPACE}/examples/web_integration_service

# Collector Service
col.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--platform ${COLLECTOR_PLATFORM} \
		--network host \
		-v ${RTI_LICENSE_MOUNT} \
		--name=$@ \
		rticom/collector-service

# Perftest
prf.pub.thr prf.pub.thr.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=${DOMAIN}-$@ \
		rticom/perftest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.pub.lat prf.pub.lat.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=${DOMAIN}-$@ \
		rticom/perftest -latencyTest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.sub prf.sub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		--name=${DOMAIN}-$@ \
		rticom/perftest \
		-sub -dataLen 1024 \
		-domain ${DOMAIN}

# Spy
spy spy.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-spy \
		-printSample \
		-domain ${DOMAIN}

# Ping
pub pub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

sub sub.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=${DOMAIN}-$@ \
		rticom/dds-ping -subscriber \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}


# Connext SDK
# Dev container requires:
#   - curl: apt install curl
#   - neovim: https://github.com/neovim/neovim?tab=readme-ov-file#install-from-package

connext-sdk-dev connext-sdk-dev.%: ensure-network
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT}:ro \
		-v home:/home \
		-v ~/.config/nvim:/home/rtiuser/.config/nvim:ro \
		-v ~/code:/home/rtiuser/code \
		-w /home/rtiuser \
		-u rtiuser \
		--name=$@ \
		${MY_DOCKER_HUB_ID}/connext-sdk-dev `# rticom/connext-sdk` \
		/bin/bash

# Remote Desktop (GUI)

# xrdp (Microsoft Remote Desktop) to localhost:3389
# ssh -p 3322 user@localhost
# Only on Linux Host: mount the graphics card:
#          --device /dev/dri:/dev/dri \
# https://github.com/hectorm/docker-xubuntu
xubuntu:
	${CONTAINER_ENGINE} run -d --rm \
	  --name $@ \
	  --shm-size 2g \
	  --publish 3322:3322/tcp  \
	  --publish 3389:3389/tcp  \
	  hectorm/xubuntu

connext-tools: ensure-network
	${CONTAINER_ENGINE} run -d --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_MOUNT} \
		-v home:/home \
		-v ~/.config/nvim:/home/user/.config/nvim:ro \
		-v ~/code:/home/user/code:ro \
		-w /home/user \
		--name $@ \
		--shm-size 2g \
		--publish 3322:3322/tcp  \
		--publish 3389:3389/tcp  \
		${MY_DOCKER_HUB_ID}/connext-tools

# Utilities

# login as 'root' user into a container
root.%: FORCE
	${CONTAINER_ENGINE} exec -u 0 -it $* bash

# login as uid '1000' user into a container
user.%: FORCE
	${CONTAINER_ENGINE} exec -u 1000 -it $* bash -c 'cd && exec bash'

# build image
#	make img.connext-sdk-dev
#	make img.connext-tools
img.%: FORCE
	-${CONTAINER_ENGINE} image rm -f ${MY_DOCKER_HUB_ID}/$*
	${CONTAINER_ENGINE} build -t ${MY_DOCKER_HUB_ID}/$* $*

# push image
#	make push.connext-sdk-dev
#	make push.connext-tools
push.%: FORCE
	${CONTAINER_ENGINE} image push ${MY_DOCKER_HUB_ID}/$*


# prune dangling comtainers and images
prune:
	${CONTAINER_ENGINE} system prune

prune_all:
	${CONTAINER_ENGINE} system prune -a
