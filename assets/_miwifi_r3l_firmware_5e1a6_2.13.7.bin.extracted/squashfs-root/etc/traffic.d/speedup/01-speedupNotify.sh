#!/bin/sh

#logger -t EbitSPEEDUP -p9 "speedup: dir:$SPEEDUP_DIR,status:$SPEEDUP_STATUS,threshold:$SPEEDUP_THRESHOLD,speed:$SPEEDUP_CUR_SPEED"

if [ "$SPEEDUP_DIR"x = "down"x ]; then
	ubus call datacenter datacenter_request '{"request":"{\"api\":634,\"pluginID\":\"2882303761517410304\",\"info\":\"{\\\"api\\\":1009}\"}"}' >/dev/null 2>&1
elif [ "$SPEEDUP_DIR"x = "up"x ]; then
        #logger -t EbitSPEEDUP -p9 "upupup"
	ubus call datacenter datacenter_request '{"request":"{\"api\":634,\"pluginID\":\"2882303761517545233\",\"info\":\"{\\\"api\\\":1009}\"}"}' >/dev/null 2>&1
else
	logger -t EbitSPEEDUP -p9 "speedup:error \$SPEEDUP_DIR must be up or down"
fi
