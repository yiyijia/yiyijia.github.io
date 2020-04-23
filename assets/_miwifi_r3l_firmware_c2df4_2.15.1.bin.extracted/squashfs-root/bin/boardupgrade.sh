#!/bin/sh
#

. /lib/upgrade/common.sh

klogger(){
	local msg1="$1"
	local msg2="$2"

	if [ "$msg1" = "-n" ]; then
		echo  -n "$msg2" >> /dev/kmsg 2>/dev/null
	else
		echo "$msg1" >> /dev/kmsg 2>/dev/null
	fi

	return 0
}

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg" >> /dev/kmsg 2>/dev/null
		if [ `pwd` = "/tmp" ]; then
			rm -rf $filename 2>/dev/null
		fi
		exit 1
	fi
}

upgrade_uboot() {
	if [ -f uboot.bin ]; then
		klogger -n "Burning uboot..."
		mtd write uboot.bin Bootloader >& /dev/null
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			exit 1
		fi
	fi
}

upgrade_firmware() {
	if [ -f firmware.bin ]; then
		klogger -n "Burning firmware..."
		mtd -r write firmware.bin OS1 >& /dev/null
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			exit 1
		fi
	fi
}

board_prepare_upgrade() {
	wifi down
	rmmod mt7628

	if [ -f "/etc/init.d/sysapihttpd" ] ;then
	    /etc/init.d/sysapihttpd stop 2>/dev/null
	fi

	# gently stop pppd, let it close pppoe session
	ifdown wan
	timeout=5
	while [ $timeout -gt 0 ]; do
	    pidof pppd >/dev/null || break
	    sleep 1
	    let timeout=timeout-1
	done

	# clean up upgrading environment
	# call shutdown scripts with some exceptions
	wait_stat=0
	klogger "Calling shutdown scripts"
	for i in /etc/rc.d/K*; do
		# filter out K01reboot-wdt and K99umount
		echo "$i" | grep -q '[0-9]\{1,100\}reboot-wdt$'
		if [ $? -eq 0 ]
		then
			klogger "$i skipped"
			continue
		fi
		echo "$i" | grep -q '[0-9]\{1,100\}umount$'
		if [ $? -eq 0 ]
		then
			klogger "$i skipped"
			continue
		fi

		if [ ! -x "$i" ]
		then
			continue
		fi

		# wait for high-priority K* scripts to finish
		echo "$i" | grep -qE "K9"
		if [ $? -eq 0 ]
		then
			if [ $wait_stat -eq 0 ]
			then
				wait
				sleep 2
				wait_stat=1
			fi
			$i shutdown 2>&1
		else
			$i shutdown 2>&1 &
		fi
	done

	# try to kill all userspace processes
	# at this point the process tree should look like
	# init(1)---sh(***)---flash.sh(***)
	for i in $(ps w | grep -v "flash.sh" | grep -v "/bin/ash" | grep -v "PID" | awk '{print $1}'); do
	        if [ $i -gt 100 ]; then
		        kill -9 $i 2>/dev/null
	        fi
	done
}

board_start_upgrade_led() {
	gpio 1 1
	gpio 3 1
	gpio l 44 2 2 1 0 4000 #led yellow flashing
}


upgrade_write_mtd() {
	curr_os=`cat /proc/mtd | grep rootfs -B 1 | head -n 1 | awk '{print $NF}' | cut -b 2-4`
	if [ "$curr_os" = "OS1" ]; then
		target_os="OS2"
	else
		target_os="OS1"
	fi

	[ -f uboot.bin ] && {
		klogger "Updating boot..."
		mtd write uboot.bin Bootloader
	}

	[ -f firmware.bin ] && {
		klogger "Updating firmware..."
		mtd write firmware.bin  "$target_os"
	}
}

board_system_upgrade() {
	local filename=$1

	mkxqimage -x $filename
	[ "$?" = "0" ] || {
		klogger "cannot extract files"
		rm -rf $filename
		exit 1
	}

	upgrade_write_mtd

	# back up etc and make sure we have enough space ( > 64kb )
	etc_size=`du -sh /data/etc | cut -d "." -f 1`
	free_size=`df -h | grep -m 1 "/etc" | awk '{print $4}' | cut -d "." -f 1`
	if [ "$(($free_size-$etc_size))" -lt "64" ]; then
		for file in /data/usr/log/*
		do
			echo "Remove logfile $file"
			rm -rf $file
			free_size=`df -h | grep -m 1 "/etc" | awk '{print $4}' | cut -d "." -f 1`
			[ "$(($free_size-$etc_size))" -gt "100" ] && break
		done
	fi

	free_size=`df -h | grep -m 1 "/etc" | awk '{print $4}' | cut -d "." -f 1`
	if [ "$(($free_size-$etc_size))" -lt "1" ]; then
		# do nothing and wait for miracles
		echo "etc fucked up"
		ls -lRh /data/etc
	else
		# backup etc
		rm -rf /data/etc_bak
		cp -prf /etc /data/etc_bak
	fi

	return 0

}
