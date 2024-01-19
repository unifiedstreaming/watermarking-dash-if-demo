![logo](https://raw.githubusercontent.com/unifiedstreaming/origin/master/unifiedstreaming-logo-black.png)


ffmpeg base image
-----------------

This image provides a generic ffmpeg instance with support for Live Media Ingest
Interface 1 (CMAF) and MSS Ingest (Smooth).


Configuration is done using environment variables:

| Variable           | Mandatory | Usage                                    |
|--------------------|-----------|------------------------------------------|
| PUB_POINT_URI      | yes       | URI used to ingest to                    |
| TRACKS             | no        | Encoder setting, defaults to `{ "video": [ { "width": 1280, "height": 720, "bitrate": "700k", "codec": "libx264", "framerate": frame_rate, "gop": gop_length, "timescale": 10000000 } ], "audio": [ { "samplerate": 48000, "bitrate": "64k", "codec": "aac", "language": "eng", "timescale": 48000 } ] }` |
| INGEST_MODE               | no        | CMAF or MSS, defaults to cmaf ingest     |