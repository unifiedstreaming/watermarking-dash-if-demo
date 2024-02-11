# vim:noexpandtab:sw=2 ts=2

.PHONY: all clean jwt test
.DEFAULT_GOAL := all

include ../../common.mk


NAME=ingress
PUBDIR_A=ingress-a
PUBDIR_B=ingress-b

PUBURL_A=$(PUBDIR_A)/$(NAME).isml
PUBURL_SIDE_CAR_A=$(PUBDIR_A)/WMPaceInfo/$(NAME).isml
MPD_A=$(PUBURL_A)/.mpd
# We tacke the sitmap from the Variant A always
SITEMAP=$(PUBURL_A)/.mpd.sitemap.xml

PUBURL_B=$(PUBDIR_B)/$(NAME).isml
PUBURL_SIDE_CAR_B=$(PUBDIR_B)/WMPaceInfo/$(NAME).isml
MPD_B=$(PUBURL_B)/.mpd


PUBURL_CACHE=${NAME}.isml

CURL_PARAMS=-f -LI -s

# Only retrieve static response headers
AWK_PARAMS_TO_WRITE_MEDIA_HEADERS_CACHE=awk -F: -v OFS=", " '\
			/^HTTP\/1.1/ { print $2 }; \
			/^Content-Type:/ { print $2 }; \
			/^WMPaceInfo:/ { print $2 }; \
			/^log:/ { print $2 }'


# Select the current sitemap.xml from varnish
# Take variant A for the sitemap
TEST_SEGMENT=$(shell curl -f -L -s http://localhost:8081/${PUBDIR_A}/${NAME}.isml/.mpd.sitemap.xml | tail -n 5 | awk -F '[<>]' '/loc/{print $$3}')

# replace .dash to .json. Usually initialization segments have a dash extension
TEST_SEGMENT_SIDE_CAR=$(patsubst %.dash,%.json,$(TEST_SEGMENT))
# or in case it it is a .m4s (media segment)
TEST_SEGMENT_SIDE_CAR=$(patsubst %.m4s,%.json,$(TEST_SEGMENT))

all: verify-synchronization

# create output folder
# create-output:
# 	mkdir -p output

verify-synchronization:
	@echo TEST_SEGMENT is: $(TEST_SEGMENT)
	@echo TEST_SEGMENT_SIDE_CAR is: $(TEST_SEGMENT_SIDE_CAR)

	@echo URL: http://localhost/${PUBURL_CACHE}/$(TEST_SEGMENT)

	curl $(CURL_PARAMS) \
		http://localhost/${PUBURL_CACHE}/$(TEST_SEGMENT) \
		| $(AWK_PARAMS_TO_WRITE_MEDIA_HEADERS_CACHE) \
		> output/header_media_segment.txt

	$(DIFF) output/header_media_segment.txt header_media_segment_reference.txt -I src

	@echo Obtaining the side-car file A
	curl $(CURL_PARAMS) \
		http://localhost:8081/$(PUBURL_SIDE_CAR_A)/$(TEST_SEGMENT_SIDE_CAR) \
		| $(AWK_PARAMS_TO_WRITE_MEDIA_HEADERS_CACHE) \
		> output/header_media_segment_side_car_a.txt

	@echo Obtaining the side-car file B
	curl $(CURL_PARAMS) \
		http://localhost:8082/$(PUBURL_SIDE_CAR_B)/$(TEST_SEGMENT_SIDE_CAR) \
		| $(AWK_PARAMS_TO_WRITE_MEDIA_HEADERS_CACHE) \
		> output/header_media_segment_side_car_b.txt

	@echo Compare variant A and B have the same content size and Sidecar file
	$(DIFF) output/header_media_segment_side_car_a.txt \
		output/header_media_segment_side_car_b.txt -I src


