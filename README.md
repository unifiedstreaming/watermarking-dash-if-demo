# watermarking-dash-if-demo


## Run PoC for VOD

![alt text for screen readers](images/USP-Varnish_VoD_Watermarking_architecture_PoC-Page1.png "VoD Watermarking functional diagram")


### Start VoD PoC

```bash
docker-compose up
```

Currently these are following A/B  variant from Origin available:
Variant A from Origin:
```bash
curl -v \
	http://localhost:8081/vod/default-blue/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll.ism/.mpd
```

Variant B from Origin:
```bash
curl -v \
	http://localhost:8081/vod/default-green/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll.ism/.mpd
```


Varnish Enterprise that produces a A/B pattern
```bash
curl -v \
	http://localhost/vod/default-green/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll.ism/.mpd
```

## This is an example of how would look the playback in DASH-IF reference player

Variant A:

![alt text for screen readers](images/variant-a.png "Variant A (blue)")

Variant B:

![alt text for screen readers](images/variant-b.png "Variant B (green)")


### Clean PoC for VOD
```bash
docker-compose down
```


### Use JWT token in VOD setup

The following is a same previous VOD asset but using
`watermarking_poc_vod_with_jwt.vcl` that only accepts requests URLs that
contains a valid JWT token as a virtual path. The following is an example
that will only work with `watermarking_poc_vod_with_jwt.vcl` configuration.
```bash
curl -v  http://localhost:8080/vod/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCIzMDAiOjEsIjMwMSI6MSwiMzAyIjoxMCwid210b2tlbi1kaXJlY3QiOnsiMzA0IjowMTEwMTExMDExfSwic3ViIjoiMTIzNDU2Nzg5MCIsImlzcyI6IjBmOThiZDNjMzMyZiJ9.rn8nyHzG1yhfzg_vuhuG6Lws_708COsopEx5Ki5cnOQ/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll.ism/.mpd > /dev/null
```

## Run PoC for live streaming

![alt text for screen readers](images/USP-Varnish_Live_Watermarking_architecture_PoC-Page1.png "Live Watermarking functional diagram")


The following live setup uses public FFmpeg image of [live-demo-cmaf](https://github.com/unifiedstreaming/live-demo-cmaf)
as git submodule. Therefore, make sure to run the following git command:

```bash
git submodule update --init --recursive
```

The following docker-compose command will build the image of FFmpeg that is
needed.

```bash
cd live
docker-compose up --build
```

Currently these are following A/B  variant from Origin available:

You will notice that the response Header from this server contains
a response Header ``X-ORIGIN: ORIGIN-A`` or ``X-ORIGIN: ORIGIN-B`` which helps
identified the two Origin servers.

Variant A from Origin:
```bash
curl -v http://localhost:8080/ingress/ingress.isml/.mpd
```

Variant B from Origin:
```bash
curl -v http://localhost:8082/ingress/ingress.isml/.mpd
```

Edge Proxy (Varnish Enterprise) seating in front of the two Origin instances:
```bash
curl -v http://localhost:8083/ingress/ingress.isml/.mpd
```

Use Manifest Edit for variant A
```bash
curl -v \
http://localhost:8080/ingress/ingress.isml/.mpd\?python_pipeline_config=mpd/default
```


Use Manifest Edit for variant B
```bash
curl -v \
http://localhost:8082/ingress/ingress.isml/.mpd\?python_pipeline_config=mpd/default
```


### This is an example of how would look the playback in DASH-IF reference player
In the following images you will notice different Active Container ID which
identifies the Variant A/B from the live streaming setup.

Variant A:

![alt text for screen readers](images/live-variant-a.png "Variant A (blue)")


Variant B:

![alt text for screen readers](images/live-variant-b.png "Variant B (green)")


### Clean PoC for LIVE
Make sure that you are running the following command from the /live folder
of the project.
```bash
docker-compose down
```


