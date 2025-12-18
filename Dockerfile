FROM ubuntu:22.04 AS builder

LABEL Maintainer=zocker-160
LABEL Fork-maintainer=hexstan

ENV HANDBRAKE_VERSION_TAG=1.10.2
ENV HANDBRAKE_DEBUG_MODE=none

ENV HANDBRAKE_URL=https://api.github.com/repos/HandBrake/HandBrake/releases/tags/$HANDBRAKE_VERSION
ENV HANDBRAKE_URL_GIT=https://github.com/HandBrake/HandBrake.git

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /HB

## Prepare
RUN apt-get update
RUN apt-get install -y \
    curl diffutils file coreutils m4 xz-utils nasm python3 python3-pip appstream software-properties-common

## Build dependencies
RUN apt-get install -y \
	autoconf automake build-essential cmake git libass-dev libbz2-dev libfontconfig-dev libfreetype-dev libfribidi-dev \
    libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev libopus-dev libsamplerate0-dev \
    libspeex-dev libtheora-dev libtool libtool-bin libturbojpeg0-dev libvorbis-dev libx264-dev libxml2-dev libvpx-dev \
    m4 make meson nasm ninja-build patch pkg-config tar

## AMD Builder
RUN apt-get install -y \
    libva-dev libdrm-dev zlib1g-dev mesa-common-dev libglu1-mesa-dev

## GTK GUI dependencies
RUN apt-get install -y \
    appstream desktop-file-utils gettext gstreamer1.0-libav gstreamer1.0-plugins-good libgstreamer-plugins-base1.0-dev \
    libgtk-4-dev

## Install clang
RUN apt-get install -y clang

## Install meson from pip
RUN pip3 install -U meson

## Download HandBrake sources
RUN echo "Downloading HandBrake sources..."
RUN git clone $HANDBRAKE_URL_GIT --branch $HANDBRAKE_VERSION_TAG

## Compile HandBrake
WORKDIR /HB/HandBrake

RUN ./scripts/repo-info.sh > version.txt

RUN echo "Compiling HandBrake..."
RUN ./configure --prefix=/usr/local \
                --debug=$HANDBRAKE_DEBUG_MODE \
                --enable-fdk-aac \
                --enable-x265 \
                --enable-numa \
                --enable-qsv \
                --enable-vce \
                --launch-jobs=$(nproc) \
                --launch

RUN make -j$(nproc) --directory=build install


##########################################################################################

## Pull base image
FROM jlesage/baseimage-gui:ubuntu-22.04-v4

ENV DEBIAN_FRONTEND=noninteractive

ENV APP_NAME="HandBrake"
ENV AUTOMATED_CONVERSION_PRESET="Very Fast 1080p30"
ENV AUTOMATED_CONVERSION_FORMAT="mp4"

# AMD GPU ENV
ENV LIBVA_DRIVER_NAME=radeonsi
ENV GST_VAAPI_ALL_DRIVERS=1
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0

## URLs
ENV APP_ICON_URL=https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/handbrake-icon.png

ENV DVDCSS_NAME=libdvd-pkg_1.4.3-1-1_all.deb
ENV DVDCSS_URL=http://ftp.br.debian.org/debian/pool/contrib/libd/libdvd-pkg/$DVDCSS_NAME

WORKDIR /tmp

## Runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    lsscsi bash coreutils yad findutils expect tcl8.6 wget git curl gpg ca-certificates software-properties-common

# AMD GPU Drivers

# Add AMD Repo (ROCm & Pro)
# Get newest OpenCL & AMF support
RUN mkdir -p /etc/apt/keyrings && \
    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/6.0.2/ubuntu jammy main proprietary" \
    > /etc/apt/sources.list.d/amdgpu.list && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.0.2 jammy main" \
    > /etc/apt/sources.list.d/rocm.list && \
    dpkg --add-architecture i386 && \
    apt-get update

# Install AMD Runtime
RUN apt-get install -y --no-install-recommends \
    mesa-vulkan-drivers \
    libvulkan1 \
    vulkan-tools \
    mesa-opencl-icd \
    opencl-headers \
    mesa-va-drivers \
    mesa-vdpau-drivers \
    libdrm-amdgpu1 \
    libdrm2 \
    vainfo \
    clinfo \
    rocm-opencl-runtime \
    amf-amdgpu-pro

## Handbrake dependencies
RUN apt-get install -y \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-fdkaac \
    libass9 \
    libavcodec-extra58 \
    libavfilter-extra7 \
    libavformat58 \
    libavutil56 \
    libbluray2 \
    libc6 \
    libcairo2 \
    libdvdnav4 \
    libdvdread8 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-4-1 \
    libgudev-1.0-0 \
    libjansson4 \
    libpango-1.0-0 \
    libsamplerate0 \
    libswresample3 \
    libswscale5 \
    libtheora0 \
    libvorbis0a \
    libvorbisenc2 \
    libx264-163 \
    libx265-199 \
    libxml2 \
    libturbojpeg

## To read encrypted DVDs install libdvdcss
RUN wget $DVDCSS_URL
RUN apt-get install -y ./$DVDCSS_NAME
RUN rm $DVDCSS_NAME

## install scripts and stuff from upstream Handbrake docker image
RUN git config --global http.sslVerify false
RUN git clone https://github.com/jlesage/docker-handbrake.git --branch v25.10.1
RUN cp -r docker-handbrake/rootfs/* /

## Cleanup
RUN rm -rf docker-handbrake /var/lib/apt/lists/* /tmp/* /var/tmp/*

## Generate and install favicons
RUN apt-get update
RUN install_app_icon.sh "$APP_ICON_URL"
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy HandBrake from base build image
COPY --from=builder /usr/local /usr

RUN getent group render || groupadd -r render
RUN getent group video || groupadd -r video

RUN set-cont-env APP_NAME "HandBrake"

# Define mountable directories
VOLUME ["/config"]
VOLUME ["/storage"]
VOLUME ["/output"]
VOLUME ["/watch"]
