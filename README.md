# debian-router-failover
Failover to LTE setup for a Debian based router.

### General
This is a failover setup for a router running Debian Linux and using a Simcom LTE module as a failover interface. It should be adaptable for other configurations as well but this is the hardware I have.

### Hardware
- APU2 (APU4D4, 120 GB mSATA SSD, case, PSU, USB to DB9F serial cable)
- Simcom SIM7600G-H LTE kit + 4G/LTE antenna with a pigtail cable

### Debian non-default packages needed
- libqmi-utils
- udhcpc

### General configuration to get LTE going

The Simcom LTE module needs a configuration which can be done with
just

```echo Y > /sys/class/net/wwan0/qmi/raw_ip```

Or rather, assuming the module's interface is wwan0:

```ip link set wwan0 down ; echo Y > /sys/class/net/wwan0/qmi/raw_ip ; ip link set wwan0 up```

At boot time this can be done with a udev rule like this:

```ACTION=="add", SUBSYSTEM=="net", ATTR{qmi/raw_ip}=="*", ATTR{qmi/raw_ip}="Y"```

The installer script puts this udev rule in /etc/udev/rules.d/simcom.rules.

### Connecting LTE

If everything is fine and the Simcom module works and has been set to
raw_ip mode as above, you an connect with first running qmicli and
then configure the interface with udhcpc.

```qmicli --device=/dev/cdc-wdm0 --device-open-proxy --wds-start-network="ip-type=4,apn=insert_your_APN_HERE" --client-no-release-cid```

You have to replace insert_your_APN_HERE with your APN, which you can
find out from your telco.

In practise, it's convenient to also enable auto-connect:

```qmicli --device=/dev/cdc-wdm0 --device-open-proxy --wds-set-autoconnect-settings=enabled,home-only --client-no-release-cid```

And then run:

```udhcpc -i wwan0```

Apparently other DHCP clients refuse to work with this kind of
interface. I've tried dhcpcd, dhclient and systemd-networkd but
nada. Good thing there's one working. Interestingly, systemd-networkd
complains that it can't set the MAC address of the wwan0 interface and
indeed it doesn't seem to have one.

### Automatic configuration of LTE

There is a script called lte_manage.sh which just runs qmicli and
udhcpc so that the LTE module connects and disconnects. The installer
will place this in /usr/local/bin. There's also a simple systemd
service to run it, which the installer will copy to
/etc/systemd/system and enable and start.

### Failover script

Failover script is called failover.sh. It's from https://www.linuxized.com/2022/01/automatic-internet-failover-to-lte-or-another-interface/. 

There are a couple parameters to edit at the top of the script,
IF_MAIN and IF_FAILOVER. In my case, IF_MAIN is enp1s0 which is the
default and IF_FAILOVER is wwan0. 

Basically failover.sh pings some hosts and if there's no response
through the main interface, it switches over to the failover
interface. It does this simply by setting the route for the failover
interface to a lower metric than your main interface.

And, if pings start working through the main interface, it switches
back.

A systemd service to start the failover.sh script is included in
failover.service.

### Files that likely need editing
- lte_env: edit for your main (IF_WAN) interface and failover interface (IF_LTE)
- lte_manage.service: 
  - Environment="LTE_DEV=/dev/cdc-wdm0" - edit to match your device.
  - Environment="LTE_APN=internet.saunalahti" - edit to match your APN.

### Installer script
I've included an installer script (installer.sh) which does just a few things:
- Copies systemd service files lte_manage.service and failover.service in /etc/systemd/system and enables them. Services are not started.
- Copies failover.sh and lte_manage.sh to /usr/local/bin.
- Copies simcom.rules to /etc/udev/rules.d/ and reloads udev rules.

### Firewall

I've included an example nftables firewall in nftables.conf. Very
typical masquerading firewall except for one thing. At the end, in the
postrouting chaing, it masquerades two interfaces. We need this so
that we can use our two interfaces.

### IP forwarding

Just a reminder, if you're going to use masquerading like in the
example firewall, you have to enable IP forwarding.

### DNS

If you run a local name server, then you need to do something so that
you can resolve names when failover is active. My simple solution is
dnsmasq and there I've specified Cloudflare's public DNS servers
1.1.1.1 and 1.0.0.1.

dnsmasq can be told what DNS servers to use over dbus so this could be
done by the failover script if needed.


