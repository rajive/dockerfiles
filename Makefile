.PHONY: *  # all targets are named recipes, that can be executed

MY_DOCKER_HUB_ID=rajive7400
RTI_LICENSE_FILE=~/rti/licenses/rti_license.dat

CONNEXT_VERSION ?= 7.7.0
CONTAINER_ENGINE ?= podman

DOMAIN=0
MY_NET=my-net

default: connext-sdk-dev

# -- My Network (bridge) ---
${MY_NET}:
	${CONTAINER_ENGINE} network create -d bridge ${MY_NET}

# --- Cloud Discovery Service ---
# must be the first container on the network
cds.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@ \
		rticom/cloud-discovery-service \
		-cfgName defaultWAN

cds.pub cds.pub.%:
	${CONTAINER_ENGINE} run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=$@ \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

cds.sub cds.sub.%:
	${CONTAINER_ENGINE} run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=$@ \
		rticom/dds-ping \
		-subscriber \
		-domain ${DOMAIN}

# --- Record and Replay ---
rec.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--mount type=volume,source=recording_service_database,target=/home/rtiuser/rti_workspace/${CONNEXT_VERSION}/database \
		--name=$@ \
		rticom/recording-service \
		-cfgName default

rpl.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--mount type=volume,source=recording_service_database,target=/home/rtiuser/rti_workspace/${CONNEXT_VERSION}/database \
		--name=$@ \
		rticom/replay-service \
		-cfgName default

# --- Persistence Service --- (fails)
mem.per.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@ \
		rticom/persistence-service \
		-cfgName default

dsk.per.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--mount type=volume,source=persistence_service_database,target=/home/rtiuser/rti_workspace/${CONNEXT_VERSION}/database \
		--name=$@ \
		rticom/persistence-service \
		-cfgName defaultDisk

per.sub per.sub.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-subscriber \
		-domain ${DOMAIN}

# --- Web Integration Service ---
web.svc:
	${CONTAINER_ENGINE} run -it --rm \
		--network host \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@ \
		rticom/web-integration-service \
		-cfgName shapesDemoTutorial \
		-documentRoot /home/rtiuser/rti_workspace/${CONNEXT_VERSION}/examples/web_integration_service

# --- Perftest ---
prf.pub.thr prf.pub.thr.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.pub.lat prf.pub.lat.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest -latencyTest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.sub prf.sub.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest \
		-sub -dataLen 1024 \
		-domain ${DOMAIN}

# --- Spy ---
spy spy.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-spy \
		-printSample \
		-domain ${DOMAIN}

# --- Ping ---
pub pub.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

sub sub.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-ping -subscriber \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}


# --- Connext SDK ---
# Dev container requires:
#   - curl: apt install curl
#   - neovim: https://github.com/neovim/neovim?tab=readme-ov-file#install-from-package

connext-sdk-dev connext-sdk-dev.%:
	${CONTAINER_ENGINE} run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat:ro \
		-v home:/home \
		-v ~/.config/nvim:/home/rtiuser/.config/nvim:ro \
		-v ~/code:/home/rtiuser/code \
		-w /home/rtiuser \
		-u rtiuser \
		--name=$@ \
		${MY_DOCKER_HUB_ID}/connext-sdk-dev `# rticom/connext-sdk` \
		/bin/bash

# --- Remote Desktop (GUI) ---

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

connext-tools:
	${CONTAINER_ENGINE} run -d --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat \
		-v home:/home \
		-v ~/.config/nvim:/home/user/.config/nvim:ro \
		-v ~/code:/home/user/code:ro \
		-w /home/user \
		--name $@ \
		--shm-size 2g \
		--publish 3322:3322/tcp  \
		--publish 3389:3389/tcp  \
		${MY_DOCKER_HUB_ID}/connext-tools

# -- Utils ---

# login as 'root' user into a container
root.%:
	${CONTAINER_ENGINE} exec -u 0 -it $* bash

# login as uid '1000' user into a container
user.%:
	${CONTAINER_ENGINE} exec -u 1000 -it $* bash -c 'cd && exec bash'

# build image
#	make img.connext-sdk-dev
#	make img.connext-tools
img.%:
	-${CONTAINER_ENGINE} image rm -f ${MY_DOCKER_HUB_ID}/$*
	${CONTAINER_ENGINE} build -t ${MY_DOCKER_HUB_ID}/$* $*

# push image
#	make push.connext-sdk-dev
#	make push.connext-tools
push.%:
	${CONTAINER_ENGINE} image push ${MY_DOCKER_HUB_ID}/$*


# prune dangling comtainers and images
prune:
	${CONTAINER_ENGINE} system prune

prune_all:
	${CONTAINER_ENGINE} system prune -a
