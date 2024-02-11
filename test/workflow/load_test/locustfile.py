##################################################
# Simple emulator of an HLS media player
##################################################
# MIT License
##################################################
# Author: Mark Ogle
# License: MIT
# Maintainer: roberto@unified-streaming.com
# Email: mark@unified-streaming.com
##################################################
import logging
import resource
import sys
import time
from datetime import datetime, timezone
from typing import Literal

from isodate import parse_duration
from locust import FastHttpUser, TaskSet, task, between
from locust.env import Environment
from locust.log import setup_logging
from locust.stats import (
    stats_printer,
    stats_history,
    StatsCSVFileWriter,
    PERCENTILES_TO_REPORT,
)
from mpegdash.parser import MPEGDASHParser
from pydantic import BaseModel
from rich import print
import typer
import gevent
import m3u8
import requests
import math

# config this stuff
BASE_URL = "https://demo.robertoramos.me"
#BASE_URL = "http://localhost"

CHANNELS = [
    # "whale.isml",
    # "whale2.isml",
    # "whale_s3.isml",
    # "ingress.isml"
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCIzMDAiOjEsIjMwMSI6MSwiMzAyIjoxMCwid210b2tlbi1kaXJlY3QiOnsiMzA0IjowMTAxMDEwMTAxfSwic3ViIjoiMTIzNDU2Nzg5MCIsImlzcyI6ImY0YTg0NWU5ZDEwNyJ9.0iEoLGTJLlJuYxIby6_krB8BNMpNwee40AyrHMgaR6c/ingress.isml"
]
# HLS_MANIFESTS = [".m3u8", ".m3u8?hls_fmp4"]
# HLS_MANIFESTS = [".m3u8"]
HLS_MANIFESTS = []
DASH_MANIFESTS = []
DASH_MANIFESTS_NUMBER = [".mpd"]

# do vbegin stuffs to test extra compute load for manifest only stuff assuming
# media segments already cached perfectly
ten_mins_ago = datetime.now(tz=timezone.utc).replace(second=0, microsecond=0)
# HLS_MANIFEST_ONLYS = [f".m3u8?vbegin={ten_mins_ago.isoformat().replace('+00:00', 'Z')}"]
# DASH_MANIFEST_ONLYS = [f".mpd?vbegin={ten_mins_ago.isoformat().replace('+00:00', 'Z')}"]
# HLS_MANIFEST_ONLYS = [".m3u8?vbegin=2022-11-29T15:10:00Z"]
# DASH_MANIFEST_ONLYS = [".mpd?vbegin=2022-11-29T15:10:00Z"]
DASH_MANIFEST_ONLYS = []

if sys.version_info[0] < 3:
    raise Exception("Must be using Python 3")

logger = logging.getLogger(__name__)
print(resource.getrlimit(resource.RLIMIT_NOFILE))


class HLSVariantPlayer(TaskSet):
    @task
    def play_stream(self):
        """
        Play complete stream.
        Steps:
        * get variant playlist
        * get last segment
        * wait for segment duration in between downloads, to act somewhat like
        a player

        kinda dumb hack to make results gathering easier is to merge
        everything into a single name
        """
        variant_url = self.parent.playlist.url
        # loop forever cuz live stream
        while True:
            ts = time.perf_counter()
            variant_m3u8 = self.client.get(
                variant_url, name=f"HLS {variant_url.replace(BASE_URL, '')} playlist"
            )
            parsed_variant_m3u8 = m3u8.M3U8(
                content=variant_m3u8.text, base_uri=variant_url
            )

            last_seg = parsed_variant_m3u8.segments[-1]

            last_seg_get = self.client.get(
                last_seg.absolute_uri,
                name=f"HLS {variant_url.replace(BASE_URL, '')} segment",
            )
            elapsed = time.perf_counter() - ts
            sleep = max(0, last_seg.duration - elapsed)
            logger.debug(
                f"Request took {elapsed} and segment duration is {last_seg.duration}. Sleeping for {sleep}"
            )
            gevent.sleep(sleep)


class HLSManifestOnlyVariantPlayer(TaskSet):
    @task
    def play_stream(self):
        """
        Play HLS stream, getting new playlist every target duration
        """
        variant_url = self.parent.playlist.url

        while True:
            ts = time.perf_counter()
            variant_m3u8 = self.client.get(
                variant_url, name=f"HLS {variant_url.replace(BASE_URL, '')} playlist"
            )
            parsed_variant_m3u8 = m3u8.M3U8(
                content=variant_m3u8.text, base_uri=variant_url
            )
            elapsed = time.perf_counter() - ts
            sleep = parsed_variant_m3u8.target_duration - elapsed
            logger.debug(
                f"Request took {elapsed} and target duration is {parsed_variant_m3u8.target_duration}. Sleeping for {sleep}"
            )
            gevent.sleep(sleep)


class DASHPlayer(TaskSet):
    @task
    def play_stream(self):
        def concurrent_request(url, name):
            self.client.get(url, name=name)

        last_time = {}

        manifest_url = self.parent.playlist.url
        manifest_base_url = manifest_url.replace("/.mpd", "")

        while True:
            manifest = self.client.get(
                manifest_url, name=f"DASH {manifest_url.replace(BASE_URL, '')} manifest"
            )
            parsed_manifest = MPEGDASHParser.parse(manifest.text)
            base_url = f"{manifest_base_url}/{parsed_manifest.periods[-1].base_urls[0].base_url_value}"
            min_upd_period = parse_duration(
                parsed_manifest.minimum_update_period
            ).seconds
            # use greenlets to request each segment in parallel
            pool = gevent.pool.Pool()
            ts = time.perf_counter()
            # get last segment from each adaptation set
            # assume segment timeline in a template at the AS level
            for adaptation_set in parsed_manifest.periods[-1].adaptation_sets:
                if (
                    adaptation_set.segment_templates[0].segment_timelines is not None
                    and len(adaptation_set.segment_templates[0].segment_timelines[0].Ss)
                    > 0
                ):
                    # find the last S with a time, then add from there
                    last_index_with_time = None
                    for i in reversed(
                        range(
                            len(
                                adaptation_set.segment_templates[0]
                                .segment_timelines[0]
                                .Ss
                            )
                        )
                    ):
                        if (
                            adaptation_set.segment_templates[0]
                            .segment_timelines[0]
                            .Ss[i]
                            .t
                        ):
                            last_index_with_time = i
                            break
                    lt = (
                        adaptation_set.segment_templates[0]
                        .segment_timelines[0]
                        .Ss[last_index_with_time]
                        .t
                    )
                    for s in (
                        adaptation_set.segment_templates[0]
                        .segment_timelines[0]
                        .Ss[last_index_with_time:]
                    ):
                        if s.r:
                            repeats = s.r
                        else:
                            repeats = 0
                        lt += s.d * (repeats + 1)

                    # check if we actually got new segments
                    if (
                        adaptation_set.id not in last_time
                        or lt > last_time[adaptation_set.id]
                    ):
                        for representation in adaptation_set.representations:
                            seg_url = (
                                adaptation_set.segment_templates[0]
                                .media.replace("$RepresentationID$", representation.id)
                                .replace("$Time$", str(lt))
                            )
                            pool.spawn(
                                concurrent_request,
                                f"{base_url}/{seg_url}",
                                name=f"DASH {manifest_url.replace(BASE_URL, '').replace('.mpd', '')}{representation.id} segment",
                            )
                        last_time[adaptation_set.id] = lt
            pool.join()
            elapsed = time.perf_counter() - ts

            # sleep for minimum update period
            sleep = min_upd_period - elapsed
            logger.debug(
                f"Requests took {elapsed} and minimum_update_period is {min_upd_period}. Sleeping for {sleep}"
            )
            gevent.sleep(sleep)


class DASHPlayerNumber(TaskSet):
    @task
    def play_stream(self):
        def concurrent_request(url, name):
            self.client.get(url, name=name)

        print("Playing stream started: play_stream()")
        last_time = {}

        manifest_url = self.parent.playlist.url
        manifest_base_url = manifest_url.replace("/.mpd", "")

        while True:
            print("While get manifest")
            manifest = self.client.get(
                manifest_url, name=f"DASH {manifest_url.replace(BASE_URL, '')} manifest"
            )
            parsed_manifest = MPEGDASHParser.parse(manifest.text)
            base_url = f"{manifest_base_url}/{parsed_manifest.periods[-1].base_urls[0].base_url_value}"
            min_upd_period = parse_duration(
                parsed_manifest.minimum_update_period
            ).seconds
            # set synthetic minimum update period for --segment_template=number
            min_upd_period = 2
            # use greenlets to request each segment in parallel
            pool = gevent.pool.Pool()
            ts = time.perf_counter()
            # get last segment from each adaptation set
            # assume segment timeline in a template at the AS level
            for adaptation_set in parsed_manifest.periods[-1].adaptation_sets:
                if (
                    adaptation_set.segment_templates[0].segment_timelines is None
                    and adaptation_set.segment_templates[0].duration > 0
                    and adaptation_set.segment_templates[0].timescale > 0
                ):
                    # find the last S with a time, then add from there
                    # last_index_with_time = None
                    duration_seconds = adaptation_set.segment_templates[0].duration / adaptation_set.segment_templates[0].timescale
                    lt = math.floor(time.mktime(datetime.today().timetuple())/duration_seconds) - 1
                    # check if we actually got new segments
                    if (
                        adaptation_set.id not in last_time
                        or lt > last_time[adaptation_set.id]
                    ):
                        for representation in adaptation_set.representations:
                            seg_url = (
                                adaptation_set.segment_templates[0]
                                .media.replace("$RepresentationID$", representation.id)
                                .replace("$Number$", str(lt))
                            )
                            # No need of forward slash after base_url
                            print(f"seg_url: {base_url}{seg_url}")
                            pool.spawn(
                                concurrent_request,
                                f"{base_url}{seg_url}",
                                name=f"DASH {manifest_url.replace(BASE_URL, '').replace('.mpd', '')}{representation.id} segment",
                            )
                        last_time[adaptation_set.id] = lt
            pool.join()
            elapsed = time.perf_counter() - ts

            # sleep for minimum update period
            sleep = min_upd_period - elapsed
            logger.debug(
                f"Requests took {elapsed} and minimum_update_period is {min_upd_period}. Sleeping for {sleep}"
            )
            gevent.sleep(sleep)


class DASHManifestOnlyPlayer(TaskSet):
    @task
    def play_stream(self):
        manifest_url = self.parent.playlist.url

        while True:
            ts = time.perf_counter()
            manifest = self.client.get(
                manifest_url, name=f"DASH {manifest_url.replace(BASE_URL, '')} .mpd"
            )
            parsed_manifest = MPEGDASHParser.parse(manifest.text)

            min_upd_period = parse_duration(
                parsed_manifest.minimum_update_period
            ).seconds
            elapsed = time.perf_counter() - ts
            sleep = min_upd_period - elapsed
            logger.debug(
                f"Request took {elapsed} and minimum_update_period is {min_upd_period}. Sleeping for {sleep}"
            )
            gevent.sleep(sleep)


class Client(TaskSet):
    def on_start(self):
        if len(playlists) > 0:
            self.playlist = playlists.pop()

    @task(1)
    def launch(self):
        if self.playlist.type == "hls":
            self.schedule_task(HLSVariantPlayer)
        elif self.playlist.type == "dash":
            self.schedule_task(DASHPlayer)
        elif self.playlist.type == "dash_number":
            self.schedule_task(DASHPlayerNumber)
        elif self.playlist.type == "hls_manifest":
            self.schedule_task(HLSManifestOnlyVariantPlayer)
        elif self.playlist.type == "dash_manifest":
            self.schedule_task(DASHManifestOnlyPlayer)


class LoadTest(FastHttpUser):
    wait_time = between(0, 0)
    host = BASE_URL
    tasks = [Client]


class Playlist(BaseModel):
    url: str
    type: Literal["dash", "dash_number","dash_manifest", "hls", "hls_manifest"]


playlists = []


def gen_urls():
    print("Generating playlist URLs")

    for channel in CHANNELS:
        if "HLS_MANIFESTS" in globals() and len(HLS_MANIFESTS) > 0:
            for hls in HLS_MANIFESTS:
                # get master, then add all variants
                print(f"Getting variants for HLS playlist: {BASE_URL}/{channel}/{hls}")
                master = requests.get(f"{BASE_URL}/{channel}/{hls}")
                parsed_master = m3u8.M3U8(
                    content=master.text, base_uri=f"{BASE_URL}/{channel}/{hls}"
                )
                for variant in parsed_master.playlists:
                    print(f"Added HLS playlist: {BASE_URL}/{channel}/{variant.uri}")
                    playlists.append(
                        Playlist(url=f"{BASE_URL}/{channel}/{variant.uri}", type="hls")
                    )
        if "HLS_MANIFEST_ONLYS" in globals() and len(HLS_MANIFEST_ONLYS) > 0:
            for hls in HLS_MANIFEST_ONLYS:
                # get master, then add all variants
                print(f"Getting variants for HLS playlist: {BASE_URL}/{channel}/{hls}")
                master = requests.get(f"{BASE_URL}/{channel}/{hls}")
                parsed_master = m3u8.M3U8(
                    content=master.text, base_uri=f"{BASE_URL}/{channel}/{hls}"
                )
                for variant in parsed_master.playlists:
                    print(f"Added HLS playlist: {BASE_URL}/{channel}/{variant.uri}")
                    playlists.append(
                        Playlist(
                            url=f"{BASE_URL}/{channel}/{variant.uri}",
                            type="hls_manifest",
                        )
                    )
        if "DASH_MANIFESTS" in globals() and len(DASH_MANIFESTS) > 0:
            for dash in DASH_MANIFESTS:
                print(f"Added DASH playlist: {BASE_URL}/{channel}/{dash}")
                playlists.append(
                    Playlist(url=f"{BASE_URL}/{channel}/{dash}", type="dash")
                )
        if "DASH_MANIFESTS_NUMBER" in globals() and len(DASH_MANIFESTS_NUMBER) > 0:
            for dash in DASH_MANIFESTS_NUMBER:
                print(f"Added DASH playlist: {BASE_URL}/{channel}/{dash}")
                playlists.append(
                    Playlist(url=f"{BASE_URL}/{channel}/{dash}", type="dash_number")
                )
        if "DASH_MANIFEST_ONLYS" in globals() and len(DASH_MANIFEST_ONLYS) > 0:
            for dash in DASH_MANIFEST_ONLYS:
                print(f"Added DASH playlist only: {BASE_URL}/{channel}/{dash}")
                playlists.append(
                    Playlist(url=f"{BASE_URL}/{channel}/{dash}", type="dash_manifest")
                )


def main(
    csv_prefix: str = typer.Option(""),
    log_level: str = typer.Option("INFO"),
    duration: int = typer.Option(60),
):
    setup_logging(log_level, None)

    gen_urls()
    # gen_urls()

    print(csv_prefix)

    env = Environment(user_classes=[LoadTest])
    env.create_local_runner()

    # really stupid hack
    tmp = sys.argv
    sys.argv = [sys.argv[0]]
    # start a WebUI instance
    env.create_web_ui("0.0.0.0", 8089)
    # sys.argv = tmp

    # start a greenlet that periodically outputs the current stats
    gevent.spawn(stats_printer(env.stats))

    # start a greenlet that save current stats to history
    gevent.spawn(stats_history, env.runner)

    # write some csvs
    now = datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")
    stats_csv_writer = StatsCSVFileWriter(
        env, PERCENTILES_TO_REPORT, f"{csv_prefix}_{now}"
    )
    gevent.spawn(stats_csv_writer.stats_writer)

    env.runner.start(len(playlists), spawn_rate=10)

    # in 60 seconds stop the runner
    gevent.spawn_later(duration, lambda: env.runner.quit())

    # stupid hack
    # sys.argv = [sys.argv[0]]

    env.runner.greenlet.join()

    # stop the web server for good measures
    env.web_ui.stop()


if __name__ == "__main__":
    typer.run(main)
