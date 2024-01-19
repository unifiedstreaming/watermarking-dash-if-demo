# ffmpeg - http://ffmpeg.org/download.html
# based on image from
# https://hub.docker.com/r/jrottenberg/ffmpeg/
#
#
FROM    alpine:3.12


ENV     X264_VERSION=20160826-2245-stable \
        X265_VERSION=x265_2.8 \
        PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
        SRC=/usr/local

RUN     buildDeps="autoconf \
                   automake \
                   bash \
                   binutils \
                   bzip2 \
                   cmake \
                   curl \
                   coreutils \
                   g++ \
                   gcc \
                   git \
                   libtool \
                   make \
                   openssl-dev \
                   tar \
                   yasm \
                   python3 \
                   pkgconfig \
                   zlib-dev" && \
        export MAKEFLAGS="-j$(($(grep -c ^processor /proc/cpuinfo) + 1))" && \
        apk add --update ${buildDeps} freetype-dev fontconfig-dev ttf-droid libgcc libstdc++ ca-certificates && \
        DIR=$(mktemp -d) && cd ${DIR} && \
        echo "**** COMPILING x264 ****" && \
        curl -sL https://download.videolan.org/pub/videolan/x264/snapshots/x264-snapshot-${X264_VERSION}.tar.bz2 | \
        tar -jx --strip-components=1 && \
        ./configure --prefix="${SRC}" --bindir="${SRC}/bin" --enable-pic --enable-shared --disable-cli && \
        make && \
        make install && \
        rm -rf ${DIR} && \
        # x265 http://www.videolan.org/developers/x265.html
        DIR=$(mktemp -d) && cd ${DIR} && \
        echo "**** COMPILING x265 ****" && \
        curl -sL https://download.videolan.org/pub/videolan/x265/${X265_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        cd build && cmake ../source && \
        make -j$(nproc) && \
        make install && \
        rm -rf ${DIR}

COPY    *.patch /root/

## ffmpeg source from github
# commit 263b98bbbda2594c44e7bf5326433d18b132f7d6 from 29/11/2020
# commit ca21cb1e36ccae2ee71d4299d477fa9284c1f551 from 12/01/2021
RUN     DIR=$(mktemp -d) && cd ${DIR} && \
        git clone https://github.com/FFmpeg/FFmpeg.git . && \
        git checkout --detach 263b98bbbda2594c44e7bf5326433d18b132f7d6 && \
        cp /root/*.patch . && \
        git apply -v *.patch && \
        ./configure --prefix="${SRC}" \
        --extra-cflags="-I${SRC}/include" \
        --extra-ldflags="-L${SRC}/lib" \
        --bindir="${SRC}/bin" \
        --disable-doc \
        --disable-static \
        --enable-shared \
        --disable-ffplay \
        --extra-libs=-ldl \
        --enable-version3 \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libfontconfig \
        --enable-libfreetype \
        --enable-gpl \
        --enable-avresample \
        --enable-postproc \
        --enable-nonfree \
        --disable-debug \
        --enable-openssl && \
        make && \
        make install && \
        make distclean && \
        hash -r && \
        rm -rf ${DIR} && \
        cd && \
        apk del ${buildDeps} && \
        rm -rf /var/cache/apk/* /usr/local/include && \
        ffmpeg -buildconf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY cmaf_ingest.py /usr/local/bin/cmaf_ingest.py
COPY cmaf_dual_ingest.py /usr/local/bin/cmaf_dual_ingest.py
COPY mss_ingest.py /usr/local/bin/mss_ingest.py
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/cmaf_ingest.py
RUN chmod +x /usr/local/bin/cmaf_dual_ingest.py

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
