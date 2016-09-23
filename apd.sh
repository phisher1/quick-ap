#!/bin/bash
## quick and dirty AP with hostapd and dnsmasq
## exit properly with ctrl-c

echo "Exit this script with Ctrl-C and it will attempt to clean up properly."

if [ -z $1 ]; then
   echo -n "SSID: "
   read ssid
else
   ssid=$1
fi

# get wep key
function get_wep_key() { 
	echo -n "WEP Key [must be exactly 5 or 13 ascii characters]: " 
	read wep_key
	if [[  $wep_key =~ ^[a-zA-Z0-9]{5}$ ]] ; then
	   echo "Key accepted"
   elif [[  $wep_key =~ ^[a-zA-Z0-9]{13}$ ]] ; then
		echo "Key accepted"
	else
		echo "WEP key must be exactly 5 or 13 characters"
		get_wep_key
	fi
}

# get mac
function get_mac() {
	echo -n "Enter MAC address in the following format AB:CD:EF:12:34:56: "
	read new_mac
	if [[  $new_mac =~ ^[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}$ ]] ; then
		macchanger --mac=$new_mac wlan0
   else
		echo "MAC Address format not correct."
		get_mac
	fi
}

# ask for WEP
echo -n "Do you want WEP enabled? [y/n]: "
read wep
case $wep in
	y*)
		get_wep_key
	;;
	*)
	;;
esac

# ask for MAC change
echo -n "Do you want to change your MAC? [y/n]: "
read changemac
case $changemac in
	y*)
		echo -n "Custom MAC? [y/n]: "
      read random_mac
		case $random_mac in
			y*)
				get_mac
			;;
			n*)
				macchanger -r wlan0
			;;
			*)
				echo "Invalid choice, keeping current MAC address."
			;;
		esac
	;;
   n*)
	;;
esac

# install packages if need be
if [ $(dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  apt-get install dnsmasq
fi
if [ $(dpkg-query -W -f='${Status}' hostapd 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  apt-get install hostapd
fi

# trap control c
trap ctrl_c INT

function ctrl_c() {
   echo "wlan0 managed mode"
   iwconfig wlan0 mode managed
   echo "downing wlan0"
   ifconfig wlan0 down
   echo "flushing firewall"
   iptables -F
   iptables -F -t nat
   echo "resetting wlan0 mac"
   macchanger -p wlan0
   kill -9 `cat /tmp/dnsmasq.run`
}


## script begins

# stop and disable services
service hostapd stop
service dnsmasq stop
pkill -9 dnsmasq
pkill -9 hostapd

# bring up wlan0
nmcli radio wifi off
rfkill unblock wlan
iwconfig wlan0 mode monitor
ifconfig wlan0 10.0.0.1/24 up

# forwarding and nat
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# dns masq conf
cat > /tmp/dnsmasq.conf <<!
bind-interfaces
interface=wlan0
dhcp-range=10.0.0.2,10.0.0.254
!

# hostapd conf
cat > /tmp/hostapd.conf<<!
interface=wlan0
driver=nl80211
ssid=${ssid}
hw_mode=g
channel=6
!

# if WEP key, add to hostapd conf
if [[ -n $wep_key ]]; then echo -e "wep_default_key=0\nwep_key0=\"${wep_key}\"" >> /tmp/hostapd.conf; fi

# run dnsmasq and hostapd
dnsmasq --pid-file=/tmp/dnsmasq.run -C /tmp/dnsmasq.conf
hostapd /tmp/hostapd.conf
