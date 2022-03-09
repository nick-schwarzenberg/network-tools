# UDP Point-to-Point Tunnel

[udp-tunnel.sh](udp-tunnel.sh) is a simple bash script to set up a network-layer point-to-point tunnel using the Linux kernel modules FOU ([foo-over-udp](https://lwn.net/Articles/614433/)) and IPIP (IP in IP) on a virtual TUN device. This is useful for exchanging IPv4 packets between two machines or networks across a link that is only capable of carrying UDP payloads.

The script [udp-tunnel-socat.sh](udp-tunnel-socat.sh) achieves essentially the same functionality in userspace using the network utility `socat`. This is useful where the Kernel modules are not available and high performance is not required. Also, the script creates only a temporary TUN device which is automatically removed on exit once SIGINT is received. This script is referred to throughout this document as “socat variant”.


## How it works

### Wrapping in UDP

The script creates an IPIP tunnel with FOU encapsulation. This tunnel wraps any IPv4 packet in another UDP/IP packet and sends it to your link's local transmit port. Your link can then transfer the UDP payload (i.e., the original IP packet) to the remote machine and discard the outer UDP/IP headers.

```
[IP-any-[payload]] -> TUN device -> [IP-UDP-[IP-any-[payload]] -> local TX port
```

In addition to the above, the script opens a receive port for incoming UDP packets. Their UDP/IP headers will be discarded and their payload (the original IP packet) will get injected into the network stack. Hence, having run the script as well on the remote side, your link can wrap the received payload in a new UDP/IP packet, send it to the configured receive port, and the tunnel is complete.

```
[IP-UDP-[IP-any-[payload]] -> remote RX port -> TUN device -> [IP-any-[payload]]
```

If your link is bi-directional (i.e., listens for UDP packets on a TX port and delivers received payloads on an RX port on each side), the tunnel will be as well (as long as the routing has been configured properly).

### Routing

To make this work, the original IP packet needs to get routed via the tunnel in the first place. Therefore, the script adds a route which tells the kernel to send packets to a given remote address or network through the tunnel. For properly handling IP packets received from the tunnel, one of the following conditions needs to be ensured:
1. The receiving end of the tunnel is already the destination *and* the destination address is known to the kernel because it's assigned to one of its network interfaces.
2. IPv4 forwarding is enabled. In this case, either:
   - The destination address belongs to a subnet of one of the kernel's network interfaces, e.g., when the destination is connected to the tunnel machine via local area network.
   - The kernel has no matching entry in its routing table, so it will be handed over to the default gateway if available (e.g., a router connected to the Internet).

Bi-directional communication with fixed IP addresses (e.g., as required for TCP or ICMP “ping” echo requests) is supported as long as any reply to the source address of the received IP packet gets routed via the tunnel. See below for some examples.


## How to use

Since the script makes changes to the kernel's network configuration, it needs to be executed with super user permissions (unless granted otherwise). Run the script without arguments to get the following instructions:
```
Usage: udp-tunnel.sh up RX_PORT TX_PORT REMOTE_IP [MTU]
       udp-tunnel.sh down RX_PORT
```
For the socat variant, there are no *up* and *down* commands. The script always attempts to create a new temporary tunnel device, keeps running until SIGINT is received, and automatically removes the tunnel on exit.

### Command line arguments

The first argument specifies the action of either setting *up* or tearing *down* the tunnel. For simplicity, it's recommended to just run the *down* command with the same following arguments as the *up* command.

**RX_PORT** – where the kernel listens for UDP packets from your link  
**TX_PORT** – where the kernel sends the wrapper UDP packets (i.e., the port your link should listen on)  
**REMOTE_IP** – the IP address or subnet to route through the tunnel  
**MTU** – *optional:* the maximum transmission unit (payload size) in Bytes that your link can handle (≥ 68, default = 1472)  

**A note on multiple tunnels on the same machine:** While this is possible, be warned that the script takes a quick-and-dirty approach on ensuring unique IPIP configurations by counting existing tunnel devices and infering both the (next) device name and local peer address from this count. If you created multiple tunnels and intend to take them down using the script, make sure to do so in opposite order, i.e., starting with the most recent. Also, make sure that no other IPIP tunnels with loopback endpoints are created meanwhile as this will break the counting.

### Examples

Say we want to connect Alice and Bob. Alice has IP address 10.0.1.2, and Bob has 10.0.2.2. Bob's network 10.0.2.0/24 can't be reached from Alice's network 10.0.1.0/24, and vice-versa.

Also, assume that we have a custom link between Alice and Bob. On each side, it sends any received payloads to localhost port 2001 and listens for UDP packets on port 2002. However, the link is only able to deliver small payloads up to 100 Bytes.

On Alice's machine, we would run:
```
$ sudo ./udp-tunnel.sh up 2001 2002 10.0.2.2 100
Loading kernel modules tun, ipip, and fou...
Checking for existing IPIP devices on loopback...
Creating FOU/IPIP tunnel device "fou1" with local peer 127.0.0.1:2002...
Setting tunnel MTU to 100 Bytes per packet...
Bringing tunnel device "fou1" up...
Opening FOU/IPIP receive port 2001 for incoming packets...
Adding route to 10.0.2.2 via tunnel...
Done.
```

On Bob's machine, we run the same command but change REMOTE_IP:
```
$ sudo ./udp-tunnel.sh up 2001 2002 10.0.1.2 100
```

Alice should now be able to ping Bob using `ping 10.0.2.2` and vice-versa. You can verify that the MTU is honored in terms of IP fragmentation by increasing the ping payload, e.g., `ping -s 128 10.0.2.2`.

If, for example, Bob is not already connected to an existing network (such as 10.0.2.0/24), Alice would have no remote IP address to refer to Bob's machine. Considering the above example, her packets to 10.0.2.2 would still pass through the tunnel due to the explicit route set up by the script, but Bob's machine wouldn't know that packets to 10.0.2.2 actually belong to Bob. In general, if we don't have IP addresses from existing networks on either side, we can always make up a network and assign respective addresses to the tunnel. Back to the above example, Bob can tell his kernel that 10.0.2.2 belongs to him by assigning this address to the tunnel device (for the socat variant, replace *fou* with *udp*):
```
$ sudo ip addr add 10.0.2.2 dev fou1
```

More things you can do:
- Route an entire subnet through the tunnel. For example, Bob can make all devices connected to his local area network 10.0.2.0/24 available to Alice. Therefore, Alice would run her script with 10.0.2.0/24 as REMOTE_IP, and Bob needs to make sure IPv4 forwarding is enabled (e.g., by running `sudo sysctl -w net.ipv4.ip_forward=1`)
- Connect to multiple machines or entirely different networks using multiple tunnels. Each tunnel can use different TX and RX ports, and hence, a different custom link of yours. If your link is able to address multiple devices, you could have your link open a TX port for each device and set up one tunnel per TX port – this way, you have a means of addressing devices on your link using IP addresses without your link ever having to deal with IP addresses itself.

### Troubleshooting

You can view a list of IPIP tunnel devices by:
```
$ ip link show type ipip
```

Note that this may include devices other than the ones created with this script. For instance, when loading the IPIP kernel module, a dummy device `tunl0` is created automatically for handling unassigned IPIP traffic. For the socat variant, you want to check instead for devices of type `tun`.

Open FOU ports accepting UDP packets (does not apply to socat variant) are shown by:
```
$ ip fou show
```

To check if and which traffic is actually sent to or received from the tunnel device, use a graphical tool such as Wireshark or run `tcpdump -i fouX -vv` where *fouX* (or *udpX*) must be one of the devices of the aforementioned list.

In case you messed up and the script failed half-way (e.g., because the tunnel device has been created but the receive port to listen at is in use), you can delete unused or broken devices by:
```
$ sudo ip link delete dev fouX
```

Since the created tunnel devices and open ports do not persist across reboots, you have to rerun the script after booting. On the other hand, if you screwed up and don't bother to clean up, you may as well just reboot to start over.
