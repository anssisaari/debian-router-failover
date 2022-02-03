#! /bin/sh

PIDDIR=/run/udhcpc
PIDFILE=${PIDDIR}/udhcpc.pid

lte_enable ()
{
    # Turn on auto-connect since apparently at boot time it's not always for sure
    # that we can connect. Roaming is turned off just in case.

    qmicli --device=$LTE_DEV --device-open-proxy \
	   --wds-set-autoconnect-settings=enabled,home-only \
	   --client-no-release-cid

    qmicli --device=$LTE_DEV --device-open-proxy \
	   --wds-start-network="ip-type=4,apn=$LTE_APN" \
	   --client-no-release-cid

    if [ ! -d $PIDDIR ]
    then
	mkdir $PIDDIR
    fi
    
    # Forks into background.
    udhcpc -i $IF_LTE -R -S -p $PIDFILE
}

lte_disable ()
{
    qmicli --device=$LTE_DEV --device-open-proxy \
	   --wds-stop-network=disable-autoconnect \
	   --client-no-release-cid

    if [ -r $PIDFILE ]
    then
	pid=`cat $PIDFILE`
	if [ -n "$PIDFILE" ]
	then
	    # I think this is excessive, we run udhcpc -R so it should release.
	    # Doesn't though and I don't know if this matters.
	    kill -SIGUSR2 $pid
	    sleep 1
	    kill $pid
	    # Just to be sure.
	    ip link set dev $IF_LTE down
	fi
    fi
}

usage ()
{
    echo $0 enable to start LTE connection.
    echo $0 disable to stop LTE connection.
}

case $1 in
    enable)
	lte_enable
	;;
    disable)
	lte_disable
	;;
    *)
	usage
	;;
esac

	  
    
