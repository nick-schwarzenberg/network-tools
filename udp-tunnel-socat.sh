#!/bin/bash
# nick.schwarzenberg@tu-dresden.de
# Mar 2022

exit_on_error () {
	if [ $? != 0 ]; then
		if [ $SOCAT_PID != "" ]; then
			kill $SOCAT_PID
		fi
		exit 1
	fi
}

print_usage_and_exit () {
	SCRIPT=`basename $0`
	echo "Usage: $SCRIPT RX_PORT TX_PORT REMOTE_IP [MTU]"
	exit 1
}



if [ `whoami` != "root" ]; then
	echo "This script needs to be run as root."
	exit 1
fi

RX_PORT=$1
TX_PORT=$2
REMOTE_IP=$3

# usual Ethernet MTU, minus IPv4 header, minus UDP header
[ "$4" != "" ] && MTU=$4 || MTU=$((1500-20-8))

echo "Checking for existing TUN devices..."
NUM_DEVICES=`ip link show type tun | wc -l`



if [ "$TX_PORT" == "" ] || [ "$RX_PORT" == "" ] || [ "$REMOTE_IP" == "" ]; then print_usage_and_exit; fi

# peer addresses and device names must be different for each tunnel
DEVICE_NAME="udp$NUM_DEVICES"

echo "Creating TUN device \"$DEVICE_NAME\"..."
socat tun,tun-name=$DEVICE_NAME,iff-no-pi udp4-sendto:127.0.0.1:$TX_PORT,bind=127.0.0.1,sourceport=$RX_PORT &
SOCAT_PID=$!
echo "socat running in background with PID $SOCAT_PID."
echo "IP in UDP/IP is sent to local port $TX_PORT and received from local port $RX_PORT."
exit_on_error

echo "Setting tunnel MTU to $MTU Bytes per packet..."
ip link set mtu $MTU dev $DEVICE_NAME
exit_on_error

echo "Bringing tunnel device \"$DEVICE_NAME\" up..."
ip link set $DEVICE_NAME up
exit_on_error

echo "Adding route to $REMOTE_IP via tunnel..."
ip route add $REMOTE_IP dev $DEVICE_NAME
exit_on_error

trap handle_sigint SIGINT
handle_sigint()
{
	echo "Caught SIGINT, cleaning up..."
	kill $SOCAT_PID  # this removes the tunnel device, automatically removing the route through it
	echo "Done."
	exit 0
}

echo "Ready. Running until SIGINT (Ctrl+C) is received."
while true; do read -n 1 -r -s key; done
