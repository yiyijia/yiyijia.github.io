#!/bin/sh

redundancy_mode=`uci get misc.log.redundancy_mode`

LOG_TMP_FILE_PATH="/tmp/xiaoqiang.log"
LOG_ZIP_FILE_PATH="/tmp/log.zip"

WIRELESS_FILE_PATH="/etc/config/wireless"
NETWORK_FILE_PATH="/etc/config/network"
MACFILTER_FILE_PATH="/etc/config/macfilter"

LOG_DIR="/data/usr/log/"
LOGREAD_FILE_PATH="/data/usr/log/messages"
LOGREAD0_FILE_PATH="/data/usr/log/messages.0"
PANIC_FILE_PATH="/data/usr/log/panic.message"
TMP_LOG_FILE_PATH="/tmp/messages"
TMP_WIFI_LOG="/tmp/wifi.log"
DHCP_LEASE="/tmp/dhcp.leases"
IPTABLES_SAVE="/tmp/iptables_save.log"
TRAFFICD_LOG="/tmp/trafficd.log"
PLUGIN_LOG="/tmp/plugin.log"
LOG_MEMINFO="/proc/meminfo"
LOG_SLABINFO="/proc/slabinfo"
DNSMASQ_CONF="/var/etc/dnsmasq.conf"
QOS_CONF="/etc/config/miqos"

hardware=`uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`

# $1 plugin install path
# $2 output file path
list_plugin(){
    for file in `ls $1 | grep [^a-zA-Z]\.manifest$`
    do
        if [ -f $1/$file ];then
            status=$(grep -n "^status " $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
            plugin_id=$(grep "name" $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
            if [ "$status"x = "5"x ]; then
		echo "$plugin_id" >> $2 # eanbled
            fi
        fi
    done
}


cat $TMP_LOG_FILE_PATH >> $LOGREAD_FILE_PATH
> $TMP_LOG_FILE_PATH

echo "==========SN" >> $LOG_TMP_FILE_PATH
nvram get SN >> $LOG_TMP_FILE_PATH

echo "==========uptime" >> $LOG_TMP_FILE_PATH
uptime >> $LOG_TMP_FILE_PATH

echo "==========df -h" >> $LOG_TMP_FILE_PATH
df -h >> $LOG_TMP_FILE_PATH

echo "==========bootinfo" >> $LOG_TMP_FILE_PATH
bootinfo >> $LOG_TMP_FILE_PATH

echo "==========tmp dir" >> $LOG_TMP_FILE_PATH
ls -lh /tmp/ >> $LOG_TMP_FILE_PATH
du -sh /tmp/* >> $LOG_TMP_FILE_PATH

echo "==========iwpriv wl0" >> $LOG_TMP_FILE_PATH
iwpriv wl0 e2p >> $LOG_TMP_FILE_PATH

echo "==========iwpriv wl1" >> $LOG_TMP_FILE_PATH
iwpriv wl1 e2p >> $LOG_TMP_FILE_PATH

echo "==========crontab" >> $LOG_TMP_FILE_PATH
crontab -l >> $LOG_TMP_FILE_PATH

echo "==========ifconfig" >> $LOG_TMP_FILE_PATH
ifconfig >> $LOG_TMP_FILE_PATH

echo "==========route" >> $LOG_TMP_FILE_PATH
route -n >> $LOG_TMP_FILE_PATH

echo "==========network:" >> $LOG_TMP_FILE_PATH
cat $NETWORK_FILE_PATH | grep -v -e'password' -e'username' >> $LOG_TMP_FILE_PATH

echo "==========wireless:" >> $LOG_TMP_FILE_PATH
cat $WIRELESS_FILE_PATH | grep -v 'key' >> $LOG_TMP_FILE_PATH

echo "==========macfilter:" >> $LOG_TMP_FILE_PATH
cat $MACFILTER_FILE_PATH >> $LOG_TMP_FILE_PATH

echo "==========ps" >> $LOG_TMP_FILE_PATH
ps >> $LOG_TMP_FILE_PATH


log_exec()
{
    echo "========== $1" >>$LOG_TMP_FILE_PATH
    eval "$1" >> $LOG_TMP_FILE_PATH
}

if [ "$hardware" = "R1D" ] || [ "$hardware" = "R2D" ]; then
    /sbin/wifi_rate.sh 6 1 >> $LOG_TMP_FILE_PATH
    for count in `seq 0 3`; do
        i=$(($count%2))
        log_exec "acs_cli -i wl$i dump bss"
        log_exec "iwinfo wl$i info"
        log_exec "iwinfo wl$i assolist"
        log_exec "wl -i wl$i dump wlc"
        log_exec "wl -i wl$i dump bsscfg"
        log_exec "wl -i wl$i dump scb"
        log_exec "wl -i wl$i dump ampdu"
        log_exec "wl -i wl$i dump dma"
        log_exec "wl -i wl$i chanim_stats"
        log_exec "wl -i wl$i counters"
        log_exec "wl -i wl$i dump stats"
        sleep 1
    done
else
#On R1CM, The follow cmd will print result to dmesg.
    iwinfo wl1 info
    iwinfo wl1 assolist
    iwpriv wl1 show stat
    iwpriv wl1 show stainfo
    iwinfo wl0 info
    iwinfo wl0 assolist
    iwpriv wl0 show stat
    iwpriv wl0 show stainfo
fi


#On R1D, the follow print to UART.
echo "==========dmesg:" >> $LOG_TMP_FILE_PATH
dmesg >> $LOG_TMP_FILE_PATH
sleep 1
echo "==========meminfo" >> $LOG_TMP_FILE_PATH
cat $LOG_MEMINFO >> $LOG_TMP_FILE_PATH

echo "==========topinfo" >> $LOG_TMP_FILE_PATH
top -b -n1 >> $LOG_TMP_FILE_PATH

echo "==========slabinfo"  >> $LOG_TMP_FILE_PATH
cat $LOG_SLABINFO >> $LOG_TMP_FILE_PATH

echo "==========dhcp:" >> $LOG_TMP_FILE_PATH
cat $DHCP_LEASE >> $LOG_TMP_FILE_PATH

echo "==========dnsmasq:" >> $LOG_TMP_FILE_PATH
cat $DNSMASQ_CONF >> $LOG_TMP_FILE_PATH

[ -f "/usr/sbin/et" ] && {
    echo "==========et port_status:" >> $LOG_TMP_FILE_PATH
    /usr/sbin/et port_status >> $LOG_TMP_FILE_PATH
}

#print out QoS rules
echo "==========QoS conf:" >> $LOG_TMP_FILE_PATH
cat $QOS_CONF >> $LOG_TMP_FILE_PATH

iptables-save -c > $IPTABLES_SAVE
ubus call trafficd hw '{"debug":true}' > $TRAFFICD_LOG

# list enabled plugin's name
list_plugin /userdisk/appdata/app_infos $PLUGIN_LOG

if [ "$redundancy_mode" = "1" ]; then
	zip -r $LOG_ZIP_FILE_PATH $LOG_TMP_FILE_PATH $LOGREAD_FILE_PATH $LOGREAD0_FILE_PATH $PANIC_FILE_PATH $TMP_WIFI_LOG $IPTABLES_SAVE $TRAFFICD_LOG $PLUGIN_LOG
else
	zip -r $LOG_ZIP_FILE_PATH $LOG_DIR $LOG_TMP_FILE_PATH $PANIC_FILE_PATH $TMP_WIFI_LOG $IPTABLES_SAVE $TRAFFICD_LOG $PLUGIN_LOG
fi

rm -f $IPTABLES_SAVE
rm -f $TRAFFICD_LOG
rm -f $PLUGIN_LOG
