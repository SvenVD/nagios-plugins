#!/bin/sh

#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA



PROGNAME=`basename $0`
VERSION="Version 0.9.1,"
AUTHOR="2013, SvenVD, svenvd.github@gmail.com"

TEMPFILE=/tmp/.prevudpstats$(id -nu)

print_version() {
    echo "$VERSION $AUTHOR"
}

print_help() {
    print_version $PROGNAME $VERSION
    echo ""
    echo "$PROGNAME is a Nagios plugin to monitor the UDP packets"
    echo "It calculates the average per packet count per minute of received, error received, unknown received and sent"
    echo ""
    echo "$PROGNAME [-uw/--uwarning] [-uc/--ucritical][-ew/--ewarning] [-ec/--ecritical]"
    echo ""
    echo "Options:"
    echo "  --uwarning|-uw)"
    echo "    Sets a warning level for packets to unknown port received. Default is: 0"
    echo "    The unit is packets/min"
    echo "  --ucritical|-uc)"
    echo "    Sets a critical level for packets to unknown port received. Default is: 0"
    echo "    The unit is packets/min"
    echo "  --ewarning|-ew)"
    echo "    Sets a warning level for packet receive errors. Default is: 0"
    echo "    The unit is packets/min"
    echo "  --ecritical|-ec)"
    echo "    Sets a critical level for packet receive errors. Default is: 0"
    echo "    The unit is packets/min"
    exit 3
}

while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit 3
            ;;
        --version|-v)
            print_version $PROGNAME $VERSION
            exit 3
            ;;
        --uwarning|-uw)
	    uwarn=$2
            shift
            ;;
        --ucritical|-uc)
	    ucrit=$2  
            shift
            ;;
        --ewarning|-ew)
	    ewarn=$2   
            shift
            ;;
        --ecritical|-ec)
	    ecrit=$2
	    
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_help
            exit 3
            ;;
    esac
    shift
done

if [ -z $uwarn ];then uwarn=0; fi
if [ -z $ucrit ];then ucrit=0; fi
if [ -z $ewarn ];then ewarn=0; fi
if [ -z $ecrit ];then ecrit=0; fi

chk_OS_version(){
	#Since output of netstat can change between OS and versions, we only allow this plugin to run on tested OS
	cat /etc/redhat-release | egrep -q "CentOS release 6.*|Fedora release 17 \(Beefy Miracle\)|CentOS release 5.*"
	if [ $? -ne 0 ];then
		echo "UNKNOWN: $(cat /etc/redhat-release) is not a supported OS"
		exit 3
	fi
}


if [ -n "$warn" -a -n "$crit" ];then
	if [ ${warn} -gt ${crit} ];then
	        echo "The warning level should be lower than the critical level. Please adjust them."
	        exit 3
	    fi
fi

chk_OS_version


#Udp stats as seen on CentOS6
#Udp:
#    4328859 packets received
#    1177 packets to unknown port received.
#    0 packet receive errors
#    7022822 packets sent

#Get previous values
touch "$TEMPFILE"

. "$TEMPFILE"


#Get current values
CHECKCMD='netstat -us'

TIMESTAMP=$(date +%s)
PCKTREC=$($CHECKCMD| egrep "packets received" | sed -n 's/^[^0-9]*\([0-9]\+\).*/\1/p')
PCKTRECUNK=$($CHECKCMD| egrep "packets to unknown port received" | sed -n 's/^[^0-9]*\([0-9]\+\).*/\1/p')
PCKTRECERR=$($CHECKCMD| egrep "packet receive errors" | sed -n 's/^[^0-9]*\([0-9]\+\).*/\1/p' )
PCKTSENT=$($CHECKCMD| egrep "packets sent" | sed -n 's/^[^0-9]*\([0-9]\+\).*/\1/p' )

#Save for next check
echo "PREVTIMESTAMP=$TIMESTAMP" > "$TEMPFILE"
echo "PREVPCKTREC=$PCKTREC" >> "$TEMPFILE"
echo "PREVPCKTRECUNK=$PCKTRECUNK" >> "$TEMPFILE"
echo "PREVPCKTRECERR=$PCKTRECERR" >> "$TEMPFILE"
echo "PREVPCKTSENT=$PCKTSENT" >> "$TEMPFILE"


#On first run previous vars will be empty, substitute by current value so diff will be 0 for all counters
if [ -z $PREVTIMESTAMP ];then PREVTIMESTAMP=$TIMESTAMP;fi
if [ -z $PREVPCKTREC ];then PREVPCKTREC=$PCKTREC;fi
if [ -z $PREVPCKTRECERR ];then PREVPCKTRECERR=$PCKTRECERR;fi
if [ -z $PREVPCKTRECUNK ];then PREVPCKTRECUNK=$PCKTRECUNK;fi
if [ -z $PREVPCKTSENT ];then PREVPCKTSENT=$PCKTSENT;fi

#Calculate differences and handle counter reset/rotation
TIMESTAMPDIFF=`expr $TIMESTAMP - $PREVTIMESTAMP`

if [ ! $PCKTREC = 0 ]
then
	PCKTRECDIFF=`expr $PCKTREC - $PREVPCKTREC`
else
	PCKTRECDIFF=0
fi

if [ ! $PCKTRECUNK = 0 ]
then
	PCKTRECUNKDIFF=`expr $PCKTRECUNK - $PREVPCKTRECUNK`
else
	PCKTRECUNKDIFF=0
fi

if [ ! $PCKTRECERR = 0 ]
then
	PCKTRECERRDIFF=`expr $PCKTRECERR - $PREVPCKTRECERR`
else
	PCKTRECERRDIFF=0
fi

if [ ! $PCKTSENT = 0 ]
then
	PCKTSENTDIFF=`expr $PCKTSENT - $PREVPCKTSENT`
else
	PCKTSENTDIFF=0
fi

#Calculate average/min

#(CUR-PREV)/(datediff/60)

if [ $TIMESTAMPDIFF -eq 0 ];then
	AVGPCKTREC=0
	AVGPCKTRECUNK=0
	AVGPCKTRECERR=0
	AVGPCKTSENT=0	
else
	AVGPCKTREC=$(echo "scale=2; $PCKTRECDIFF/($TIMESTAMPDIFF/60) "| bc -l)
	AVGPCKTRECUNK=$(echo "scale=2; $PCKTRECUNKDIFF/($TIMESTAMPDIFF/60) "| bc -l)
	AVGPCKTRECERR=$(echo "scale=2; $PCKTRECERRDIFF/($TIMESTAMPDIFF/60) "| bc -l)
	AVGPCKTSENT=$(echo "scale=2; $PCKTSENTDIFF/($TIMESTAMPDIFF/60) "| bc -l)
fi

#Construct performance data output

PERFDATA="'avg_udp_received pckts/min'=${AVGPCKTREC}c 'avg_udp_unknown_port pckts/min'=${AVGPCKTRECUNK}c;$uwarn;$ucrit 'avg_udp_errors pckts/min'=${AVGPCKTRECERR}c;$ewarn;$ecrit 'avg_udp_sent pckts/min'=${AVGPCKTSENT}c"

#Alerting logic (since bash can not handle floating point comparisions, we use bc for the purpose)

if [ $(echo "$AVGPCKTRECUNK > $ucrit" | bc -l) -eq 1 -o $(echo "$AVGPCKTRECERR > $ecrit" | bc -l) -eq 1 ];then
	echo "CRITICAL: $AVGPCKTRECERR pckts/min receive errors, $AVGPCKTRECUNK pckts/min unknown ports | $PERFDATA"
	exit 2
elif [ $(echo "$AVGPCKTRECUNK > $uwarn" | bc -l) -eq 1 -o $(echo "$AVGPCKTRECERR > $ewarn" | bc -l) -eq 1 ];then
	echo "WARNING: $AVGPCKTRECERR pckts/min receive errors, $AVGPCKTRECUNK pckts/min unknown ports | $PERFDATA"
	exit 1
else
	echo "OK: no udp packet errors or packets to unknown ports rate exceeded thresholds  | $PERFDATA"
	exit 0
fi

