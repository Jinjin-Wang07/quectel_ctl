FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        build-essential \
        busybox \
        ca-certificates \
        cmake \
        curl \
        git \
        iproute2 \
        iputils-ping \
        libudev-dev \
        minicom \
        net-tools \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        screen \
        sudo \
        usbutils \
        udev \
        vim \
    && rm -rf /var/lib/apt/lists/*