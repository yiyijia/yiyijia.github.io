#!/bin/sh
#firewall.parentalctl_1=rule
#firewall.parentalctl_1.src=lan
#firewall.parentalctl_1.dest=wan
#firewall.parentalctl_1.src_mac=D0:4F:7E:C0:D5:5D
#firewall.parentalctl_1.proto=tcp
#firewall.parentalctl_1.extra=-m time --weekdays Mon,Tue,Wed,Thu,Fri,Sat,Sun --timestart 9:10 --timestop 09:35
#firewall.parentalctl_1.extra=-m time --weekdays Mon,Tue,Wed,Thu,Fri --datestart 2015-06-19T06:20 --datestop 2015-06-19T06:25 
#firewall.parentalctl_1.target=REJECT

#rule
#iptables -t filter -A FORWARD -m mac --mac-source 14:F6:5A:D3:8A:A1  -m time --weekdays Mon,Tue,Wed,Thu,Fri --timestart 20:00 --timestop 09:00 -j REJECT
#iptables -t filter -A FORWARD -m mac --mac-source 14:F6:5A:D3:8A:A1  -m time --weekdays Mon,Tue,Wed,Thu,Fri --timestart 20:00 --timestop 09:00 -j REJECT

#iptables -t filter -A FORWARD -m mac --mac-source D0:4F:7E:C0:D5:5D  -m time  --datestart 2015-06-19T14:20 --datestop 2015-06-19T14:20 -p tcp -j REJECT --kerneltz
#iptables -t filter -I FORWARD   -m time  --datestart 2015-06-19T14:20 --datestop 2015-06-19T15:25 -p tcp -j REJECT --kerneltz

#iptables -t nat -A PREROUTING -m mac --mac-source D0:4F:7E:C0:D5:5D  -m time  --datestart 2015-06-19T14:20 --datestop 2015-06-19T14:55 -p tcp -j DNAT --to 127.0.0.1 --kerneltz 
#        option extra '-m time --weekdays Mon,Tue,Wed,Thu,Fri,Sat,Sun --timestart 9:10 --timestop 09:35'

#parental control 配置
#config global global
#        option start_time       21:00
#        option stop_time        09:00
#        option weekdays         'mon tue wed thu fri'
#        list hostfile '/etc/parentalctl/catagory4.url'
#        list hostfile '/etc/parentalctl/catagory2.url'

#weekdays
#config device
#        option mac 'D0:4F:7E:C0:D5:5D'
#        option weekdays 'Mon,Tue,Wed,Thu,Fri'
#        list time_seg '09:00-09:45'
#        list time_seg '11:00-14:00'

#everyday
#config device
#        option mac 'D0:4F:7E:C0:D5:33'
#        list time_seg '09:00-09:45'
#        list time_seg '11:00-14:00'
#        option weekdays 'Mon Tue Wed Thu Fri Sat Sun'
#        list hostfile '/etc/parentalctl/catagory3.url'
#        list hostfile '/etc/parentalctl/catagory2.url'

#once
#config device
#        option mac 'D0:4F:7E:C0:D5:11'
#        option start_date '2014-05-19'
#        option stop_date '2014-05-20'
#        list time_seg '09:00-09:45'
#        list time_seg '11:00-14:00'
#        list hostfile '/etc/parentalctl/catagory2.url'

#config device
#        option mac 'D0:4F:7E:C0:D5:22'
#        option weekdays 'Mon Tue Wed Thu Fri'
#        list time_seg '09:00-09:45'
#        list time_seg '11:00-14:00'
#        list hostfile '/etc/parentalctl/catagory1.url'
#        list hostfile '/etc/parentalctl/catagory2.url'

#firewall uci 配置
#config rule 'parentalctl_global'
#        option src              lan
#        option dest             wan
#        option src_mac          00:01:02:03:04:05
#        option start_date       2015-06-18
#        option stop_date        2015-06-20
#        option start_time       21:00
#        option stop_time        09:00
#        option weekdays         'mon tue wed thu fri'
#        option target           REJECT
#
#config rule parentalctl_1
#        option src              lan
#        option dest             wan
#        option src_mac          00:01:02:03:04:05
#        option start_date       2015-06-18
#        option stop_date        2015-06-20
#        option start_time       21:00
#        option stop_time        09:00
#        option weekdays         'mon tue wed thu fri'
#        option target           REJECT
. /lib/functions.sh

dnsmasq_conf_path="/etc/dnsmasq.d/"
parentalctl_conf_path="/etc/parentalctl/"
parentalctl_conf_name="parentalctl.conf"

rule_prefix="parentalctl_"
ipset_name="parentalctl_"

time_seg=""
weekdays=""
hosts=""
src_mac=""
start_date=""
stop_date=""

device_set=""

local _pctl_file="$parentalctl_conf_path"/"$parentalctl_conf_name"
local _has_pctl_file=0
local _dnsmasq_file="$dnsmasq_conf_path"/"$parentalctl_conf_name"

local time_cntr=0

pctl_logger()
{
    echo "parentalctl: $1"
    logger -t parentalctl "$1"
}

dnsmasq_restart()
{
    process_pid=$(ps | grep "/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf" |grep -v "grep /usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf" | awk '{print $1}' 2>/dev/null)
    process_num=$( echo $process_pid |awk '{print NF}' 2>/dev/null)
    process_pid1=$( echo $process_pid |awk '{ print $1; exit;}' 2>/dev/null)
    process_pid2=$( echo $process_pid |awk '{ print $2; exit;}' 2>/dev/null)


    [ "$process_num" != "2" ] && /etc/init.d/dnsmasq restart

    retry_times=0
    while [ $retry_times -le 3 ]
    do
        let retry_times+=1
        /etc/init.d/dnsmasq restart
        sleep 1

        process_newpid=$(ps | grep "/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf" |grep -v "grep /usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf" | awk '{print $1}' 2>/dev/null)
        process_newnum=$( echo $process_newpid |awk '{print NF}' 2>/dev/null)
        process_newpid1=$( echo $process_newpid |awk '{ print $1; exit;}' 2>/dev/null)
        process_newpid2=$( echo $process_newpid |awk '{ print $2; exit;}' 2>/dev/null)

        pctl_logger "old: $process_pid1 $process_pid2 new: $process_newpid1 $process_newpid2"

        [ "$process_pid1" == "$process_newpid1" ] && continue;
        [ "$process_pid1" == "$process_newpid2" ] && continue;
        [ "$process_pid2" == "$process_newpid1" ] && continue;
        [ "$process_pid2" == "$process_newpid2" ] && continue;

        break
    done
}

#format 2015-05-19
date_check()
{
    local _date=$1

    [ "$_date" == "" ] && return 0

    if echo $_date | grep -iqE "^2[0-9]{3}-[0-1][0-9]-[0-3][0-9]$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "date \"$_date\" format(2xxx-xx-xx) error";
         return 1
    fi

    return 0
}

#format "09:20-23:59"
time_check()
{
    local _time_set=$1
    local _time=""

    [ "$_time_set" == "" ] && return 0

    for _time in $_time_set
    do
        if echo $_time | grep -iqE "^[0-2][0-9]:[0-6][0-9]-[0-2][0-9]:[0-6][0-9]$"
        then
            #echo mac address $mac format correct;
            return 0
        else
            echo "time \"$_time\" format(09:20-23:59) error";
            return 1
        fi
    done

    return 0
}

#format 01:02:03:04:05:06
#  mini 00:00:00:00:00:00
#  max  ff:ff:ff:ff:ff:ff
mac_check()
{
    local _mac=$1

    [ "$_mac" == "" ] && return 0

    if echo $_mac | grep -iqE "^([0-9A-F]{2}:){5}[0-9A-F]{2}$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "mac address \"$mac\" format(01:02:03:04:05:06) error";
         return 1
    fi

    return 0
}

#Mon Tue Wed Thu Fri Sat Sun
weekdays_check()
{
    local _weekdays=$1

    [ "$_weekdays" == "" ] && return 0

    if echo $_weekdays |grep -iqE "^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)( (Mon|Tue|Wed|Thu|Fri|Sat|Sun)){0,6}$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "weekdays \"$_weekdays\" format error";
         echo "  format \"Mon Tue Wed Thu Fri Sat Sun\",1-7 items"
         return 1
    fi

    return 0
}

pctl_config_entry_check()
{
    time_check "$time_seg" || return 1
    date_check "$start_date" || return 1
    date_check "$stop_date" || return 1
    mac_check "$src_mac"    || return 1
    weekdays_check "$weekdays" || return 1

    return 0;
}

pctl_config_entry_init()
{
    time_seg=""
    weekdays=""
    hostfile=""
    src_mac=""
    start_date=""
    stop_date=""
    disabled=""

    return
}

parentalctl_ipset_add() 
{
    local _ipsetname="$1"
    ipset list | grep $_ipsetname  > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        ipset create $_ipsetname  hash:ip > /dev/null 2>&1
    fi
}

local _ipset_cache_file="/tmp/parentalctl.ipset"
rm $_ipset_cache_file 2>/dev/null

parse_hostfile_one()
{
    local _hostfile=$1
    local _ipsetname=$2
    local _tempfile="/tmp/parentctl.tmp"

    rm $_tempfile 2>/dev/null
    echo hostfileone"$1 $2"

    format2domain -f $_hostfile -o $_tempfile
    if [ $? -ne 0 ]; then
        echo "format2domain error!"
        return 1
    fi
 
    cat $_tempfile | while read line
    do
        _has_pctl_file=1
        echo "$line $_ipsetname"
    done >> $_ipset_cache_file

    cat $_ipset_cache_file

    rm $_tempfile 2>/dev/null

    parentalctl_ipset_add $_ipsetname
    return 0;
}

parse_hostfile_finish()
{

    sort $_ipset_cache_file | uniq > $_ipset_cache_file".2"
    
    awk '{
        if($1==x) 
        {
            i=i","$2
        } 
        else 
        { 
            if(NR>1) { print i} ; 
            i="ipset=/"$1"/"$2 
        }; 
        x=$1;
        y=$2
    }
    END{print i}' $_ipset_cache_file".2" > $_pctl_file
    
    rm $_ipset_cache_file
    rm $_ipset_cache_file".2"
  
    return 0
}

#firewall 规则
#
#config rule 'parentalctl_global'
#        option src              lan
#        option dest             wan
#        option src_mac          00:01:02:03:04:05
#        option start_date       2015-06-18
#        option stop_date        2015-06-20
#        list time_seg '09:00-09:45'
#        list time_seg '11:00-14:00'
#        option weekdays         'mon tue wed thu fri'
#        option target           REJECT
parse_global()
{
    local section="$1"
    local _buffer=""

    pctl_config_entry_init
    config_get disabled   $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get time_seg   $section time_seg &>/dev/null;
    config_get weekdays   $section weekdays &>/dev/null;
    config_get hostfiles  $section hostfile &>/dev/null;
    config_get start_date $section start_date &>/dev/null;
    config_get stop_date  $section stop_date &>/dev/null;

    append _buffer "set firewall.parentalctl_global=rule"$'\n'
    append _buffer "set firewall.parentalctl_global.src='lan'"$'\n'
    append _buffer "set firewall.parentalctl_global.dest='wan'"$'\n'
    append _buffer "set firewall.parentalctl_global.extra='--kerneltz'"$'\n'
    append _buffer "set firewall.parentalctl_global.target='REJECT'"$'\n'
    append _buffer "set firewall.parentalctl_global.proto='TCP UDP'"$'\n'

    pctl_config_entry_check || return

    for one_time_seg_flaged in $time_seg
    do
        #list time_seg '1_01:00-02:00'
        time_seg_flag=$(echo $one_time_seg_flaged |cut -d _ -f 1 2>/dev/null)
        [ $time_seg_flag != "1" ] && {
            continue
        }

        one_time_seg=$(echo $one_time_seg_flaged |cut -d _ -f 2 2>/dev/null)

        start_time=$(echo $one_time_seg |cut -d - -f 1 2>/dev/null)
        stop_time=$(echo $one_time_seg |cut -d - -f 2 2>/dev/null)

        append _buffer "set firewall.parentalctl_global.src_mac='$src_mac'"$'\n'

        #all day
        [ "$start_time" == "" -a "$stop_time" == "" ] && {
            append _buffer "set firewall.parentalctl_global.start_time='00:00'"$'\n'
            append _buffer "set firewall.parentalctl_global.stop_time='23:59'"$'\n'
        }

        #special time
        [ "$start_time" != "" -a "$stop_time" != "" ] && {
            append _buffer "set firewall.parentalctl_global.start_time='$start_time'"$'\n'
            append _buffer "set firewall.parentalctl_global.stop_time='$stop_time'"$'\n'
        }

        #everyday equals all 7 days in one week
        #mon tue wed thu fri sat sun
        [ "$weekdays" != "" ] && {
            append _buffer "set firewall.parentalctl_global.weekdays='$weekdays'"$'\n'
        }

        #once
        [ "$start_date" != "" -a "$stop_date" != "" ] && {
            append _buffer "set firewall.parentalctl_global.start_date='$start_date'"$'\n'
            append _buffer "set firewall.parentalctl_global.stop_date='$stop_date'"$'\n'
        }
    done

    local _device_has_hostfile=0
    for hostfile in $hostfiles
    do
        [ ! -f "$hostfile" ] && continue

        parse_hostfile_one "$hostfile" "${ipset_name}global"

        _device_has_hostfile=1
        _has_pctl_file=1
    done

    [ $_device_has_hostfile == 1 ] && {
        append _buffer "set firewall.parentalctl_global_host=rule"$'\n'
        append _buffer "set firewall.parentalctl_global_host.src='lan'"$'\n'
        append _buffer "set firewall.parentalctl_global_host.dest='wan'"$'\n'
        append _buffer "set firewall.parentalctl_global_host.target='REJECT'"$'\n'
        append _buffer "set firewall.parentalctl_global_host.proto='TCP UDP'"$'\n'
        append _buffer "set firewall.parentalctl_global_host.extra='-m set --match-set ${ipset_name}global dst'"$'\n'
        #append _buffer "set firewall.parentalctl_global_host.ipset='${ipset_name}global'"$'\n'
    }

uci -q batch <<-EOF >/dev/null
    $_buffer
    commit firewall
EOF

     return 0;
}

#config rule parentalctl_1
#        option src              lan
#        option dest             wan
#        option src_mac          00:01:02:03:04:05
#        option start_date       2015-06-18
#        option stop_date        2015-06-20
#        option start_time       21:00
#        option stop_time        09:00
#        option weekdays         'mon tue wed thu fri'
#        option target           REJECT
parse_device()
{
    local section="$1"
    local _buffer=""

    local device_id=""
    
    pctl_config_entry_init

    config_get disabled   $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get src_mac    $section mac &>/dev/null;
    [ "$src_mac" == "" ] && return ;

    config_get time_seg   $section time_seg &>/dev/null;
    config_get weekdays   $section weekdays &>/dev/null;
    config_get start_date $section start_date &>/dev/null;
    config_get stop_date  $section stop_date &>/dev/null;

    pctl_config_entry_check || return 0;

    #mac 01:02:03:04:05:06 ->> id 010203040506
    device_id=${src_mac//:/};
    
    for one_time_seg in $time_seg
    do
        start_time=$(echo $one_time_seg |cut -d - -f 1 2>/dev/null)
        stop_time=$(echo $one_time_seg |cut -d - -f 2 2>/dev/null)

        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}=rule"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.name='$rule_prefix'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.src='lan'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.dest='wan'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.extra='--kerneltz'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.target='REJECT'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.proto='TCP UDP'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.src_mac='$src_mac'"$'\n'

        #all day
        [ "$start_time" == "" -a "$stop_time" == "" ] && {
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.start_time='00:00'"$'\n'
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.stop_time='23:59'"$'\n'
        }

        #special time
        [ "$start_time" != "" -a "$stop_time" != "" ] && {
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.start_time='$start_time'"$'\n'
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.stop_time='$stop_time'"$'\n'
        }

        #everyday equals all 7 days in one week
        #mon tue wed thu fri sat sun
        [ "$weekdays" != "" ] && {
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.weekdays='$weekdays'"$'\n'
        }

        #once
        [ "$start_date" != "" -a "$stop_date" != "" ] && {
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.start_date='$start_date'"$'\n'
            append _buffer "set firewall.parentalctl_${device_id}_${time_cntr}.stop_date='$stop_date'"$'\n'
        }

        let time_cntr+=1
    done

    #echo "###########################################################sa"
    echo " $_buffer"
    echo "###########################################################"

#do not commit firewall
uci -q batch <<-EOF >/dev/null
    $_buffer
    commit firewall
EOF

    return 0;
}

parse_rule()
{
    local section="$1"
    local _buffer=""
    local device_id=""
    local _mode=""
    local _mode_extra=""

    pctl_config_entry_init

    config_get disabled   $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get src_mac    $section mac &>/dev/null;
    [ "$src_mac" == "" ] && return ;

    config_get hostfiles  $section hostfile &>/dev/null;

    #mode = [white|black], if mode not set, means black
    config_get _mode $section mode &>/dev/null;

    [ "$_mode" == "white" ] && _mode_extra="!"

    pctl_config_entry_check || return 0;

    #mac 01:02:03:04:05:06 ->> id 010203040506
    device_id=${src_mac//:/};

    local _device_has_hostfile=0
    for hostfile in $hostfiles
    do
        [ ! -f "$hostfile" ] && continue

        parse_hostfile_one "$hostfile" "${ipset_name}${device_id}"

        _device_has_hostfile=1
        _has_pctl_file=1
    done

    [ $_device_has_hostfile == 1 ] && {
        append _buffer "set firewall.parentalctl_${device_id}_dns=redirect;"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.name='$rule_prefix'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.src='lan';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.dest='wan';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.src_dport='53';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.dst_port='53';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.target='dnat';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.proto='TCP UDP';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_dns.src_mac='$src_mac';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host=rule;"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.name='$rule_prefix'"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.src='lan';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.dest='wan';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.target='REJECT';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.proto='TCP UDP';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.src_mac='$src_mac';"$'\n'
        append _buffer "set firewall.parentalctl_${device_id}_host.extra=' -m set $_mode_extra --match-set ${ipset_name}${device_id} dst ';"$'\n'
    }

    #echo "###########################################################sa"
    echo "host $_buffer"
    echo "###########################################################"

#do not commit firewall
uci -q batch <<-EOF >/dev/null
    $_buffer
    commit firewall
EOF

}

pctl_fw_add_all()
{
    pctl_config_entry_init

    config_load "parentalctl"

    #config_foreach parse_global global

    config_foreach parse_device device

    config_foreach parse_rule rule
    parse_hostfile_finish

#finally commit firewall here
uci -q batch <<-EOF >/dev/null
    commit firewall
EOF

    [ "$_has_pctl_file" == "0" -a -f "$_dnsmasq_file" ] && {
        rm $_dnsmasq_file 2>/dev/null
        dnsmasq_restart
    }

    [ "$_has_pctl_file" != "0" ] && {
        rm $_dnsmasq_file 2>/dev/null
        cp $_pctl_file $_dnsmasq_file
        dnsmasq_restart
    }

    return 0
}

pctl_fw_delete_all()
{
    local delete_cmd=$(uci show firewall | awk -F= '{if($1~/^firewall.'$rule_prefix'/)  print "del "$1 }')

uci -q batch <<-EOF >/dev/null
    $delete_cmd

    commit firewall
EOF

    return 0
}

pctl_iptables_delete_all()
{
    rule_num_set=$(iptables -L -t filter --line-number 2>/dev/null |grep $rule_prefix | awk '{print $1}' |sort -n -r )
    echo "$rule_num_set"
    for rule_num in $rule_num_set
    do
        iptables -D zone_lan_forward $rule_num
    done
}

pctl_iptables_add_all()
{
    _tempfile="/tmp/"$rule_prefix"add_all.txt"

    pctl_iptables_delete_all

    fw3 print 2>/dev/null| grep $rule_prefix | awk '{gsub(/-A/,"-I",$4); print $0}'  > $_tempfile
    cat $_tempfile | while read line
    do
        echo $line
        $line
    done
   
}

pctl_flush()
{
    pctl_iptables_delete_all

    pctl_fw_delete_all

    pctl_fw_add_all

    #iptables add all must run after fw add, because we need "fw3 print"
    pctl_iptables_add_all
    return 0
}

fw3lock="/var/run/fw3.lock"
trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
lock $fw3lock

pctl_flush

lock -u $fw3lock






