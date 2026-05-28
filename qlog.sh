#!/usr/bin/env bash 
QUECTEL_DIR="./quectel_qlog/out"
QD="$QUECTEL_DIR"
 
function usage {
    echo "usage: script.sh outfile"
    echo "       logs will be stored in quectel_qlog/out/outfile as outfile.qmdl2"
    exit 1
}

echo $#

if [[ $# < 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
fi

mkdir $QD/tmp -p
mkdir $QD/logs/$1 -p
ln -sf $QD/logs/

logs="$QD/logs/$1"

$QD/QLog -p /dev/ttyUSB0 -s $QD -f $QD/../conf/defaultNR5G1216.cfg -q 

mv $QD/*.qmdl2 $logs/$1.qmdl2
