#!/bin/sh
# Copyright (C) 2015 Xiaomi
. /lib/functions.sh

uci -q batch <<-EOF >/dev/null
    set ustack.settings.enabled=1
    commit ustack
EOF

