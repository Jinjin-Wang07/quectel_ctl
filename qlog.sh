#!/usr/bin/env bash 
QUECTEL_DIR="./quectel_qlog/out"
QD="$QUECTEL_DIR"
 
function usage {
    echo "usage: script.sh outfile [config]"
    echo "       logs will be stored in quectel_qlog/out/outfile"
    exit 1
}

if [[ $# < 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
fi

mkdir $QD/tmp -p
mkdir $QD/logs/$1 -p
ln -sf $QD/logs/

logs="$QD/logs/$1"

if [[ -z "$2" ]]; then
    $QD/QLog -p /dev/ttyUSB0 -s $QD -f ./quectel_qlog/conf/defaultNR5G1216.cfg -q
else
    $QD/QLog -p /dev/ttyUSB0 -s $QD -f "$2" -q
fi

QDB="$logs/$1.qdb"
QMDL2="$logs/$1.qmdl2"

mv $QD/*.qmdl2 $QMDL2
mv $QD/*.qdb $QDB

scat -t qc -d $QDML2 --qsr4-hash $QDB -F $logs/$1.pcap

echo "Thank you for using qlog.sh output files are in $logs"

