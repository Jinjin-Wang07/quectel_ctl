# How to use
## Premade scripts
You can use the premade qlog.sh script which automatically captures from a QC chipset and dumps the verbose PCAP info
```./qlog.sh file_name [config]```
Output files are generated to:
```./quectel_qlog/out/logs/file_name```

## Manual commands:
```./QLog -p /dev/ttyUSB0 -s . -f ../conf/defaultNR5G1216.cfg -q```
```scat -t qc -d quectel_qlog/out/20260525_204002_0000.qmdl2```
