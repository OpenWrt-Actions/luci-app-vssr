#!/bin/bash
# Copyright (C) 2019 Jerryk <jerrykuku@qq.com>
python=python3
host=$1
if echo $host | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then
    hostip=${host}
elif [ "$host" != "${host#*:[0-9a-fA-F]}" ]; then
    hostip=${host}
else
    hostip=`nslookup ${host} | grep 'Address 1' | sed 's/Address 1: //g'`
    if echo $hostip | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then
        hostip=${hostip}
    else
        hostip=$(cat /etc/ssr_ip)
    fi
fi


$python -c "import maxminddb;import json;reader = maxminddb.open_database('/usr/share/vssr/GeoLite2-Country.mmdb');aa = reader.get('${hostip}');reader.close();print(aa['country']['iso_code'].lower())"
