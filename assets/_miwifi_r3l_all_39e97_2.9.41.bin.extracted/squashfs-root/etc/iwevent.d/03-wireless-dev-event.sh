#!/bin/sh

[ -n "$STA" ] && {
	   [ "$ACTION" = "ASSOC" ] && {
		  logger -t miqos -p9 "STA up $ACTION $STA"
          /etc/init.d/miqos device_in $STA
	   }

       [ "$ACTION" = "DISASSOC" ] && {
          logger -t miqos -p9 "STA down $ACTION $STA"
          /etc/init.d/miqos device_out $STA
       }
}

