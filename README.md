# Forensic A/B Watermarking DASH-IF Demo

We present an implementation overview of the architecture of DASH-IF Forensic A/B Watermarking.

- https://doi.org/10.1145/3638036.3640251

- [ETSI TS 104 002 Publicly Available Specification (PAS); DASH-IF Forensic A/B Watermarking version 1.1.1 8-2023. An interoperable watermarking integration schema.](https://www.etsi.org/deliver/etsi_ts/104000_104099/104002/01.01.01_60/ts_104002v010101p.pdf)



## Run PoC for VOD

![alt text for screen readers](images/USP-Varnish_Live_Watermarking_architecture_PoC-Page1.png "Live Watermarking functional diagram")



## Run PoC for live streaming


The following docker-compose command will build the image of FFmpeg that is
needed.

```bash
make setup-3 USP_LICENSE_KEY=$USP_LICENSE_KEY
```

Currently these are following A/B  variant from Origin available:

You will notice that the response Header from this server contains
a response Header ``X-ORIGIN: ORIGIN-A`` or ``X-ORIGIN: ORIGIN-B`` which helps
identified the two Origin servers.

Example stream with the following WM pattern 0101010101
```bash
curl -v \
http://localhost/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCIzMDAiOjEsIjMwMSI6MSwiMzAyIjoxMCwid210b2tlbi1kaXJlY3QiOnsiMzA0IjowMTAxMDEwMTAxfSwic3ViIjoiMTIzNDU2Nzg5MCIsImlzcyI6ImY0YTg0NWU5ZDEwNyJ9.0iEoLGTJLlJuYxIby6_krB8BNMpNwee40AyrHMgaR6c/ingress.isml/.mpd
```

Example stream with the following pattern 0000011111
```bash
http://localhost/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCIzMDAiOjEsIjMwMSI6MSwiMzAyIjoxMCwid210b2tlbi1kaXJlY3QiOnsiMzA0IjowMDAwMDExMTExfSwic3ViIjoiMTIzNDU2Nzg5MCIsImlzcyI6ImY0YTg0NWU5ZDEwNyJ9.qXenxnAql5Lkil5kRJ6BIqlf4tD4nL08PUlcDMMr5AU/ingress.isml/.mpd
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
make clean-setup-3
```


