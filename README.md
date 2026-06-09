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

## 5. Parse and Check Logs with SCAT

Use SCAT to parse Quectel QLog dump files (`.qmdl2`) and validate parsed PCAP output.

### Setup SCAT environment

Run the setup helper:

```bash
./3_setup_scat.sh
```

What this script does:
- creates a local virtual environment at `.venv-scat`
- installs SCAT from `./scat` in editable mode with `fastcrc`
- installs `tshark` if it is missing

Activate the environment:

```bash
source .venv-scat/bin/activate
```

### Example of dump file parsing

```bash
scat -t qc -d quectel_qlog/log/20260608_154826_0000.qmdl2 -F out.pcap
```

### Check parsed PCAP result

1. Activate SCAT virtual environment:

```bash
source .venv-scat/bin/activate
```

2. Run the automated parser + checker pipeline:

```bash
./4_check_pcap_result.sh
```

This command will:
- read `.qmdl2` files from `quectel_qlog/log` (or `quectel_qlog/out/logs`)
- copy source logs to `./output`
- parse `.qmdl2` to `.pcap` using `scat`
- validate each `.pcap` contains both `RRC Setup` and `RRC Reconfiguration`


3. Optional: run with explicit paths:

```bash
./4_check_pcap_result.sh ./quectel_qlog/log ./scat/wireshark/scat.lua
```

4. Check generated outputs:

```bash
ls -lh ./output
```

Expected checker result:
- `[OK] Found both: RRC Setup and RRC Reconfiguration`

5. Optional: open generated PCAP files in Wireshark and verify control-plane signaling is visible (NAS/RRC over GSMTAP).

If Wireshark does not decode some LTE/NR layers, install the SCAT Lua plugin from `scat/wireshark/scat.lua` into your Wireshark plugin directory.

