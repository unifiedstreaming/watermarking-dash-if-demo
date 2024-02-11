#!/bin/bash

set -e


INPUT_URLS_FILE=abs_urls_s3_research_dash.txt # To use with a media player test


FOLDER=output
TEST_SUBFOLDER=$(date "+%Y-%m-%d-%H:%M:%S")
OUTPUT_FOLDER=$FOLDER/$TEST_SUBFOLDER

VARNISH_CONTAINER_NAME=varnish-cache-proxy
DOCKER=docker
DOCKER_COMPOSE="docker compose"
PYTHON=python3
LOAD_TEST=



# Silly way to make sure Apache is ready for any request.
start_compse_file () {
	local compose_file="$1"
	local host_name_uri="$2"
	cd ../../
	echo "compose_file:" $compose_file
	$DOCKER_COMPOSE -f $compose_file up -d
	echo "Waiting for docker-compose to be ready ..."
	#curl -s -o /dev/null  $host_name_uri
	sleep 10
	cd test/workflow
	# $(COMPOSE) -f docker-compose-live-watermarking-setup-1.yml up  \
	# 	$(COMPOSE_EXT_PARAMS)
}

stop_compose_file () {
	local compose_file="$1"
	echo "PWD: $PWD"
	cd ../../
	echo "Stopping docker-compose ..."
	$DOCKER_COMPOSE down --remove-orphans
	echo "PWD: $PWD"
	cd test/workflow
}


create_output_folder () {
	echo "OUTPUT_FOLDER: $OUTPUT_FOLDER"
	mkdir -p $OUTPUT_FOLDER
}

iterate_test_urls () {
	# Test using a dash.js or hls.js player
	# This method iterates per URL stream
	local cache_status="$1"; # cold/warm
	while IFS='=' read -r key url; do
		echo ""
		echo "URL: $url"
		echo "Test name: $key"
		echo "File: $OUTPUT_FOLDER/$key-$cache_status.json"
		#vst_evaluation --url=$url --output=$OUTPUT_FOLDER/$key-$cache_status.json
		$(PYTHON) locustfile.py --csv-prefix=test-1-gen-urls 
		#get_varnish_metrics $OUTPUT_FOLDER/$key-$cache_status.log
		#get_varnishncsa_logs $OUTPUT_FOLDER/$key-$cache_status-requests.log
	done < "$INPUT_URLS_FILE"
}


test_wm_varnish () {
	local compose_file="$1"
	local locust_prefix="$2"
	echo "Initializing docker-compose:  '$compose_file'"
	create_output_folder
	start_compse_file $compose_file 'https://demo.robertoramos.me/'
	echo "Request varnistat metrics before the test ..."
	local time_now=$(date "+%Y-%m-%dT%H:%M:%S")
	echo "time_now: $time_now"
	$DOCKER exec -it $VARNISH_CONTAINER_NAME varnishstat -n varnish -1 >& $locust_prefix-$time_now-start-varnishstat.log
	$PYTHON load_test/locustfile.py --csv-prefix=$locust_prefix
	$DOCKER exec -it $VARNISH_CONTAINER_NAME varnishstat -n varnish -1 >& $locust_prefix-$time_now-end-varnishstat.log
	$DOCKER container logs --tail=1000 varnishncsa >& $locust_prefix-$time_now-varnishlog.log
	sleep 2
	stop_compose_file $compose_file
}


for i in {1..10}
do
	echo "********** Running iteratin number: $i  **********"
	# test_wm_varnish "docker-compose-live-watermarking-setup-1.yml" "results/test-setup-1-gen-urls-$i-"
	# sleep 5
	# test_wm_varnish "docker-compose-live-watermarking-setup-2.yml" "results/test-setup-2-gen-urls-$i-"
	# sleep 5
	# test_wm_varnish "docker-compose-live-watermarking-setup-2-one-side-car.yml" "results/test-setup-2-one-side-car-gen-urls-$i-"
	# sleep 5
	test_wm_varnish "docker-compose-live-watermarking-setup-3.yml" "results/test-setup-3-gen-urls-$i-"
	sleep 5
	# test_wm_varnish "docker-compose-live-watermarking-setup-4.yml" "results/test-setup-4-gen-urls-$i-"
	# sleep 5
done

