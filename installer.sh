#! /bin/sh

if [[ "$UID" -ne 0 ]]
then
    echo "Run as root please."
    exit
fi

# params: $1 file name, $2 target dir, $3 perms
condcopy () {
    if [[ ! -d "$2" ]]
    then
	echo $2 doesn\'t exist, not creating.
	return
    fi

    if [[ ! -f $2/$1 ]]
    then
	install --mode=$3 $1 $2
    else
	echo $2/$1 exists, not overwriting.
    fi
}

# systemd services
condcopy lte_manage.service /etc/systemd/system 644
condcopy failover.service /etc/systemd/system 644
condcopy lte_env /etc/systemd/system 644

# scripts 
condcopy lte_manage.sh /usr/local/bin 755
condcopy failover.sh /usr/local/bin 755

# udev rule
condcopy simcom.rules /etc/udev/rules.d 644

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Enable services
systemctl enable failover.service
systemctl enable lte_manage.service

# Start services
# Let's maybe not.
#systemctl start failover.service
#systemctl start lte_manage.service

echo Everything is ready to go but check your firewall before
echo starting failover.service and lte_manage.service.
