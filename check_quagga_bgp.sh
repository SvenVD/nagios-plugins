#!/bin/bash
#SvenVD 2014
#Note this only has been tested on Centos6 with quagga-0.99.15-7


#Initialization
VERSION="0.4"
PERCENTPEERS=0
NR_ESTA_PEERS=0
PERCPEERS=0
IPPROT=v6
TW_MINPEERS=100
TC_MINPEERS=100
TW_STATEPPFXRCD=1
EXITCODES=0 

#Functions
# Print help along with usage
print_help()
{
    echo "Nagios plugin to check quagga bgp"
    echo "Version $VERSION, by SvenVD, svenvd.github@gmail.com"

    echo -e "\n$USAGE\n"

    echo "Parameters description:"
    echo " -p|--ipprot <v4/v6>		       # Monitor ipv6 peers(the default) or ipv4 peers"
    echo " -wmp|--warnminpeers <threshold>     # Minimum percentage of established peers, default 100%, anything below this thresh is warning"   
    echo " -cmp|--critminpeers <threshold>     # Minimum percentage of established peers, default 100%, anything below this thresh is critical" 
    echo " -wpr|--warnminprefix <threshold>    # Every peer should have at least <warnminprefix> prefixes"                     
    echo " -h|--help                           # Print this message"
}

while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit 3
            ;;
        -p|--ipprot)
	    if [ $2 = "v4" -o $2 = "v6" ]; then
	    	IPPROT=$2
	    else
		print_help
	    fi
            shift
            ;;
        -wmp|--warnminpeers)
      	    TW_MINPEERS=$2
            shift
            ;;
        -cmp|--critminpeers)
      	    TC_MINPEERS=$2
            shift
            ;;
        -wpr|--warnminprefix)
            TW_STATEPPFXRCD=$2
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

#Start

#Do not forget to add command alias to sudoers
#Cmnd_Alias  NRPE_QUAGGA_BGP_CMNDS = /usr/bin/vtysh -c show ip bgp summary, /usr/bin/vtysh -c show ipv6 bgp summary
if [ $IPPROT = v4 ];then
	BGPDATA=$(sudo /usr/bin/vtysh -c 'show ip bgp summary' | head -n -2 | sed '1,6d' | egrep "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" )
elif [ $IPPROT = v6 ];then
	BGPDATA=$(sudo /usr/bin/vtysh -c 'show ipv6 bgp summary'  | head -n -2 | sed '1,6d' |  awk '
	BEGIN{i=1}{line[i++]=$0}
	END{j=1; 
	  while (j<i){
		split(line[j],array);
		if ( array[2]=="" ) { 
			print line[j] line[j+1]; j+=2
		} else {
			print line[j]; j+=1
		}
	  }
    }'
)		
fi


while read line;do

  IP=$(echo $line | cut -d" " -f1)
  UPDOWN=$(echo $line | cut -d" " -f9)
  STATEPPFXRCD=$(echo $line | cut -d" " -f10)
  
  #Needs to match 37w2d00h or 1d18h50m or 23:39:12 and $STATEPPFXRCD is not a state but a count
  if [[ "$UPDOWN" =~ ^[0-9]{1,2}[a-z:][0-9]{1,2}[a-z:][0-9]{1,2}[a-z:]{0,1} && "$STATEPPFXRCD" =~ ^[0-9]+$ ]];then
    #This means UPDOWN is in established state
    NR_ESTA_PEERS=$(( $NR_ESTA_PEERS +1 ))
    PERFDATA="$PERFDATA""$IP=$STATEPPFXRCD;$TW_STATEPPFXRCD;; "
    #This also means we got some prefixes, compare them with threshold
    if [ $STATEPPFXRCD -lt $TW_STATEPPFXRCD ];then
	PEERSPREFIXERR="$PEERSPREFIXERR""$IP->$TW_STATEPPFXRCD"
	EXITCODES="$EXITCODES"" 1"
    else
	EXITCODES="$EXITCODES"" 0"
    fi
  else
    PEERS_NOT_ESTA="$PEERS_NOT_ESTA""$IP->$STATEPPFXRCD / " 
    PERFDATA="$PERFDATA""$IP=0;$TW_STATEPPFXRCD;; "
  fi
  NRPEERS=$(( $NRPEERS +1 ))

done <<< "$BGPDATA"
#Strip last char
PEERS_NOT_ESTA=$(echo $PEERS_NOT_ESTA | sed 's/\/$//')
PEERSPREFIXERR=$(echo $PEERSPREFIXERR | sed 's/\/$//')

#Check for minimum percentage of established peers
test $NR_ESTA_PEERS -eq 0 || PERCPEERS=$(echo "scale=2; ($NR_ESTA_PEERS/$NRPEERS)*100" | bc -l)

#Alerting logic (since bash can not handle floating point comparisions, we use bc for the purpose)

if [ -n "$PEERSPREFIXERR" ];then
  MSGNAGIOS="$MSGNAGIOS""Prefixes for peers $PEERSPREFIXERR below thresholds:: "
fi

if [ $(echo "$PERCPEERS < $TC_MINPEERS" | bc -l) -eq 1 ];then
  MSGNAGIOS="$MSGNAGIOS""Only $PERCPEERS% of peers are in established state (required: $TW_MINPEERS%).$(( $NRPEERS - $NR_ESTA_PEERS )) Erroneous peers: $PEERS_NOT_ESTA :: "
  EXITCODES="$EXITCODES"" 2"
elif [ $(echo "$PERCPEERS < $TW_MINPEERS" | bc -l) -eq 1 ];then
  MSGNAGIOS="$MSGNAGIOS""Only $PERCPEERS% of peers are in established state (required: $TW_MINPEERS%).$(( $NRPEERS - $NR_ESTA_PEERS )) Erroneous peers: $PEERS_NOT_ESTA :: "
  EXITCODES="$EXITCODES"" 1"
else
  #Do not output OK message if we already have a non-OK message
  if ! echo "$EXITCODES" | egrep -q "1|2|3";then
  	MSGNAGIOS="$MSGNAGIOS""$PERCPEERS% of $IPPROT peers are in established state"
  fi
  EXITCODES="$EXITCODES"" 0"
fi


####Substitute all : from PERFDATA output
PERFDATA=$(echo "$PERFDATA" | sed 's/:/_/g')

####Generate nagiosoutput
if  echo "$EXITCODES" | grep -q 2;then
	echo "CRITICAL: $MSGNAGIOS|$PERFDATA"	
	exit 2;
elif  echo "$EXITCODES" | grep -q 1;then
	echo "WARNING: $MSGNAGIOS|$PERFDATA"	
	exit 1;
elif  echo "$EXITCODES" | grep -q 3;then
	echo "UNKNOWN: $MSGNAGIOS|$PERFDATA"	
	exit 3;
else
	echo "OK: $MSGNAGIOS|$PERFDATA"	
	exit 0
fi
