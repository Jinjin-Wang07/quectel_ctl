# Quectel Log Collection Toolkit

This repository is used to collect cellular network logs with Quectel modems.

It contains:
- `quectel_QCom/`: QConnectManager (`quectel-CM`) tools
- `quectel_qlog/`: QLog diagnostic capture tool
- `scat/`        : qmdl log parsing tool

## 1. Clone the repository (with submodules)

```bash
git clone --recursive https://github.com/Jinjin-Wang07/quectel_ctl.git
cd quectel_ctl
```

If you already cloned without `--recursive`, run:

```bash
git submodule update --init --recursive
```

## 2. Option A: Build on the host

### Prerequisites

Recommended host machine: **Ubuntu 24.04**.

Install required packages:

```bash
sudo apt-get update
sudo apt-get install -y build-essential usbutils
```

`1_setup.sh` performs the build for both QCom and QLog.

### Build QCom + QLog

```bash
./1_setup.sh
```

QConnectManager binaries are generated under `quectel_QCom/out/`, including:
- `quectel-CM`
- `quectel-cm-test`

The QLog binary is generated at:
- `quectel_qlog/out/QLog`

## 3. Option B: Build and run inside a Docker container

This method uses Docker directly.

### Build the image

```bash
docker build -t quectel-ubuntu-24.04 -f .devcontainer/Dockerfile .
```

### Start the container

Run this cmd in the quectel_ctl folder
```bash
docker run -it --name quectel-ubuntu-24.04 \
	--privileged \
	--device-cgroup-rule='c 188:* rmw' \
	-v /dev:/dev \
	--network=host \
	-v "$PWD":/workspaces/$(basename "$PWD") \
	-w /workspaces/$(basename "$PWD") \
	-u root \
	quectel-ubuntu-24.04 bash
```

### Compile inside the container

```bash
./1_setup.sh
```

## 4. 5G Network Log Collection

Use the integrated helper script:

```bash
sudo ./2_run_5g_capture.sh
```

What this script does:
- checks `/dev/ttyUSB2` (AT port) and `/dev/cdc-wdm0`
- sends `ATI` on the AT port and verifies modem vendor contains `quectel`
- starts QLog with `quectel_qlog/conf/defaultNR5G1216.cfg`
- starts QCom test with `quectel_QCom/configs/qcm-5g.conf`

### Expected output (network registration)

Check the regular status message from `quectel-cm-test` during runtime, if QCom status snapshots show `AT+QNWINFO` containing `NR5G` and a band such as `NR5G BAND XX`, the modem is connected to the 5G network.

Example:

```text
[06-05_17:22:36:178] status snapshot: after connect wait
[06-05_17:22:36:183] modem-info command: AT+QNWINFO
[06-05_17:22:36:183] modem-info response: +QNWINFO: "FDD NR5G","23410","NR5G BAND 28",152690
[06-05_17:22:36:183] modem-info response: OK
```

### Verify IP and data connectivity

Check `wwan0` IP address on another console:

```bash
ip addr show wwan0
```

Test connectivity from `wwan0`:

```bash
ping -I wwan0 8.8.8.8
```

