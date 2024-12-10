.PHONY: *  # all targets are named recipes, that can be executed

RTI_LICENSE_FILE=~/rti/licenses/rti_license.dat
DOMAIN=0
MY_DOCKER_HUB_ID=rajive7400
MY_NET=my-net

default: connext-sdk-dev

# -- My Network (bridge) ---
${MY_NET}:
	docker network create -d bridge ${MY_NET}

# --- Cloud Discovery Service ---
# must be the first container on the network
cds.svc:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@ \
		rticom/cloud-discovery-service \
		-cfgName defaultWAN

cds.pub cds.pub.%:
	docker run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=$@ \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

cds.sub cds.sub.%:
	docker run -it --rm \
		-e NDDS_DISCOVERY_PEERS="rtps@udpv4://cds.svc:7400" \
		--network ${MY_NET} \
		--name=$@ \
		rticom/dds-ping \
		-subscriber \
		-domain ${DOMAIN}

# --- Record and Replay ---
rec.svc:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--mount type=volume,source=recording_service_database,target=/home/rtiuser/rti_workspace/7.3.0/database \
		--name=$@ \
		rticom/recording-service \
		-cfgName default

rpl.svc:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--mount type=volume,source=recording_service_database,target=/home/rtiuser/rti_workspace/7.3.0/database \
		--name=$@ \
		rticom/replay-service \
		-cfgName default

# --- Persistence Service --- (fails)
mem.per.svc:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@ \
		rticom/persistence-service \
		-cfgName default

dsk.per.svc:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--mount type=volume,source=persistence_service_database,target=/home/rtiuser/rti_workspace/7.3.0/database \
		--name=$@ \
		rticom/persistence-service \
		-cfgName defaultDisk

per.sub per.sub.%:
	docker run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-subscriber \
		-domain ${DOMAIN}

# --- Web Integration Service ---
web.svc:
	docker run -it --rm \
		--network host \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@ \
		rticom/web-integration-service \
		-cfgName shapesDemoTutorial \
		-documentRoot /home/rtiuser/rti_workspace/7.3.0/examples/web_integration_service

# --- Perftest ---
prf.pub.thr prf.pub.thr.%:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.pub.lat prf.pub.lat.%:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest -latencyTest \
		-pub -dataLen 1024 -executionTime 60 \
		-domain ${DOMAIN}

prf.sub prf.sub.%:
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		--name=$@-${DOMAIN} \
		rticom/perftest \
		-sub -dataLen 1024 \
		-domain ${DOMAIN}

# --- Spy ---
spy spy.%:
	docker run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-spy \
		-printSample \
		-domain ${DOMAIN}

# --- Ping ---
pub pub.%:
	docker run -it --rm \
		--network ${MY_NET} \
		--name=$@-${DOMAIN} \
		rticom/dds-ping \
		-reliable \
		-durability TRANSIENT_LOCAL \
		-domain ${DOMAIN}

sub sub.%:
	docker run -it --rm \
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
	docker run -it --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat:ro \
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
	docker run -d --rm \
	  --name $@ \
	  --shm-size 2g \
	  --publish 3322:3322/tcp  \
	  --publish 3389:3389/tcp  \
	  hectorm/xubuntu

connext-tools:
	docker run -d --rm \
		--network ${MY_NET} \
		-v ${RTI_LICENSE_FILE}:/opt/rti.com/rti_connext_dds-7.3.0/rti_license.dat \
		-v home:/home \
		-v ~/.config/nvim:/home/user/.config/nvim:ro \
		-w /home/user \
		--name $@ \
		--shm-size 2g \
		--publish 3322:3322/tcp  \
		--publish 3389:3389/tcp  \
		${MY_DOCKER_HUB_ID}/connext-tools

# -- Utils ---

# login as 'root' user into a container
root.%:
	docker exec -u 0 -it $* bash

# login as uid '1000' user into a container
user.%:
	docker exec -u 1000 -it $* bash -c 'cd && exec bash'

# build image
#	make img.connext-sdk-dev
#	make img.connext-tools
img.%:
	-docker image rm -f ${MY_DOCKER_HUB_ID}/$*
	docker build -t ${MY_DOCKER_HUB_ID}/$* $*

# push image
#	make push.connext-sdk-dev
#	make push.connext-tools
push.%:
	docker image push ${MY_DOCKER_HUB_ID}/$*


# prune dangling comtainers and images
prune:
	docker system prune

prune_all:
	docker system prune -a
