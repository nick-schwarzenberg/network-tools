#!/bin/bash
#
# SPDX-FileCopyrightText: 2020 Nick Schwarzenberg <nick.schwarzenberg@tu-dresden.de>
# SPDX-License-Identifier: MIT



exit_on_error () {
	if [ $? != 0 ]; then
		exit 1
	fi
}

print_usage_and_exit () {
	SCRIPT=`basename $0`
	echo "Usage: $SCRIPT up RX_PORT TX_PORT REMOTE_IP [MTU]"
	echo "       $SCRIPT down RX_PORT"
	exit 1
}



if [ `whoami` != "root" ]; then
	echo "This script needs to be run as root."
	exit 1
fi

ACTION=$1
RX_PORT=$2
TX_PORT=$3
REMOTE_IP=$4

if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ]; then print_usage_and_exit; fi

# usual Ethernet MTU, minus IPv4 header, minus UDP header
[ "$5" != "" ] && MTU=$5 || MTU=$((1500-20-8))

if [ "$ACTION" == "up" ]; then
	echo "Loading kernel modules tun, ipip, and fou..."
	modprobe -a tun ipip fou
	exit_on_error
fi

echo "Checking for existing IPIP devices on loopback..."
NUM_DEVICES=`ip link show type ipip | grep 'peer 127.0.0.' | wc -l`



if [ "$ACTION" == "up" ]; then

	if [ "$TX_PORT" == "" ] || [ "$RX_PORT" == "" ] || [ "$REMOTE_IP" == "" ]; then print_usage_and_exit; fi

	# peer addresses and device names must be different for each tunnel
	NEXT_NUM=$(($NUM_DEVICES+1))
	IPIP_PEER="127.0.0.$NEXT_NUM"
	DEVICE_NAME="fou$NEXT_NUM"

	echo "Creating FOU/IPIP tunnel device \"$DEVICE_NAME\" with local peer $IPIP_PEER:$TX_PORT..."
	ip link add name $DEVICE_NAME type ipip \
		remote $IPIP_PEER local any \
		encap fou encap-sport auto encap-dport $TX_PORT
	exit_on_error

	echo "Setting tunnel MTU to $MTU Bytes per packet..."
	ip link set mtu $MTU dev $DEVICE_NAME
	exit_on_error

	echo "Bringing tunnel device \"$DEVICE_NAME\" up..."
	ip link set $DEVICE_NAME up
	exit_on_error

	echo "Opening FOU/IPIP receive port $RX_PORT for incoming packets..."
	ip fou add port $RX_PORT ipproto 4
	exit_on_error

	echo "Adding route to $REMOTE_IP via tunnel..."
	ip route add $REMOTE_IP dev $DEVICE_NAME
	exit_on_error

else

	if [ $NUM_DEVICES -eq 0 ]; then
		echo "No devices found, nothing to take down."
		exit 1
	fi

	if [ "$RX_PORT" == "" ]; then print_usage_and_exit; fi

	DEVICE_NAME="fou$NUM_DEVICES"

	echo "Closing receive port $RX_PORT..."
	ip fou delete port $RX_PORT
	exit_on_error

	echo "Taking tunnel device \"$DEVICE_NAME\" down..."
	ip link set $DEVICE_NAME down
	exit_on_error

	echo "Deleting tunnel device \"$DEVICE_NAME\"..."
	ip link delete dev $DEVICE_NAME
	exit_on_error

fi

echo "Done."
exit 0
