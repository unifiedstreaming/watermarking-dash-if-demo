.PHONY: all clean jwt test varnishd live
.DEFAULT_GOAL := all
.SECONDARY:

COMPOSE=docker compose
COMPOSE_EXT_PARAMS=--force-recreate

all:
	docker-compose up $(COMPOSE_EXT_PARAMS)


### Live
setup-1:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-1.yml up  \
		$(COMPOSE_EXT_PARAMS)

clean-setup-1:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-1.yml down  \
		--remove-orphans

setup-2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2.yml up   \
		$(COMPOSE_EXT_PARAMS)

restart-setup-2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2.yml restart  \
		-t 30 varnish-cache-proxy

clean-setup-2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2.yml down  \
		--remove-orphans

setup-v2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2-one-side-car.yml up   \
		$(COMPOSE_EXT_PARAMS)

restart-setup-v2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2-one-side-car.yml restart  \
		-t 30 varnish-cache-proxy

clean-setup-v2:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-2-one-side-car.yml down  \
		--remove-orphans


setup-3:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-3.yml up  --build \
		$(COMPOSE_EXT_PARAMS)

clean-setup-3:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-3.yml down  \
		--remove-orphans

setup-4:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-4.yml up \
		$(COMPOSE_EXT_PARAMS)

clean-setup-4:
	$(COMPOSE) -f docker-compose-live-watermarking-setup-4.yml down  \
		--remove-orphans


test: test-vod test-live

test-vod: jwt
	sleetp 5
	$(MAKE) -C test/side-car all
	$(MAKE) -C test/wm-pattern all
	$(MAKE) -C test/wm-token all
	$(MAKE) clean-vod

test-live: wm-live
	@echo Add sleep to make sure the containers are deployed. Also the \
	availability_start_time=10
	sleep 15
	$(MAKE) -C test/live-side-car all
	$(MAKE) clean-live
