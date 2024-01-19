.PHONY: all clean jwt test varnishd live
.DEFAULT_GOAL := all
.SECONDARY:

COMPOSE=docker-compose
COMPOSE_EXT_PARAMS=

all:
	docker-compose up $(COMPOSE_EXT_PARAMS)


origin:
	$(COMPOSE) -f docker-compose-jwt.yml up -d unified-origin \
		$(COMPOSE_EXT_PARAMS)

varnishd:
	$(COMPOSE) -f docker-compose-jwt.yml up varnishd $(COMPOSE_EXT_PARAMS)

jwt:
	$(COMPOSE) -f docker-compose-jwt.yml up -d varnishd-jwt \
		$(COMPOSE_EXT_PARAMS)
	@echo "Waiting for docker compose to be deployed"
	sleep 5

clean-vod:
	docker-compose -f docker-compose-jwt.yml down

live-demo-cmaf:
	cd live; $(COMPOSE) -f docker-compose-live-demo-cmaf.yml up \
		$(COMPOSE_EXT_PARAMS)

live:
	cd live; $(COMPOSE) -f docker-compose.yml up clear
		$(COMPOSE_EXT_PARAMS)

wm-live:
	cd live; $(COMPOSE) -f docker-compose-live-watermarking.yml up  --build \
		$(COMPOSE_EXT_PARAMS)

clean-live:
	cd live; $(COMPOSE) -f docker-compose-live-watermarking.yml down \
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
