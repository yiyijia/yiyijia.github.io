#! /bin/sh

echo $1

ip addr | grep $1 > /dev/NULL
ret=$?

if [ $ret == 1 ]; then
        ip addr add $1/24 dev br-lan
fi
