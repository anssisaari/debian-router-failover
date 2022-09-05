#! /bin/sh

PIDDIR=/run/udhcpc
PIDFILE=${PIDDIR}/udhcpc.pid

# This is so that when we're not called from systemd, we still know our device.
if [ -z "$LTE_DEV" ]
then
	. /etc/systemd/system/lte_env
fi

lte_enable ()
{
    qmi-network $LTE_DEV start
    # Forks into background.
    udhcpc -i $IF_LTE -R -S -p $PIDFILE -s /etc/udhcpc/lte.script
}

lte_disable ()
{
    qmi-network $LTE_DEV stop

    if [ -r $PIDFILE ]
    then
	pid=`cat $PIDFILE`
	if [ -n "$pid" ]
	then
	    # I think this is excessive, we run udhcpc -R so it should release.
	    # Doesn't though and I don't know if this matters.
	    kill -USR2 $pid
	    sleep 1
	    kill $pid
	    # Just to be sure.
	    ip link set dev $IF_LTE down
	fi
    fi
}

lte_status ()
{
    qmi-network $LTE_DEV status
}

usage ()
{
    echo $0 enable to start LTE connection.
    echo $0 disable to stop LTE connection.
    echo $0 status to show LTE connection status.
}

case $1 in
    enable)
	lte_enable
	;;
    disable)
	lte_disable
	;;
    status)
	lte_status
	;;
    *)
	usage
	;;
esac

	  
    
