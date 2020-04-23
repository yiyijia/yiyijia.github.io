#!/bin/sh
# Copyright (C) 2015 Xiaomi
. /lib/functions.sh

old_timeout=$(uci get wifishare.global.auth_timeout 2>/dev/null)
[ "$old_timeout" == "30" ] && { uci set wifishare.global.auth_timeout=60; uci commit wifishare;}

guest_configed=$(uci get wireless.guest_2G  2>/dev/null)
isolate_configed=$(uci get wireless.guest_2G.ap_isolate  2>/dev/null)
guest_ssid=$(uci get wireless.guest_2G.ssid 2>/dev/null)

guest_suffix=$(getmac |cut -b 13-17 |sed 's/://g' |tr '[a-z]' '[A-Z]')
#guest_ssid="Xiaomi_${guest_suffix}_VIP"
[ "$guest_configed" != "" ] && [ "$isolate_configed" == "" ] && {
    uci set wireless.guest_2G.ap_isolate=1;
    uci commit wireless
}

#guest default format Xiaomi_xxxx_VIP
#guest_ssid_matched=$(echo $guest_ssid | grep "^Xiaomi_[[:xdigit:]]\{4\}_VIP$")
[ "$guest_ssid" == "Xiaomi_${guest_suffix}_VIP" ] && {
    uci set wireless.guest_2G.ssid="小米共享WiFi_${guest_suffix}";
    uci commit wireless
}
