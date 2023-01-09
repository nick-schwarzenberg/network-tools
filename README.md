# Network Tools

This repository holds convenience scripts to easily set up point-to-point tunnels via the Linux kernel modules FOU ([foo-over-udp](https://lwn.net/Articles/614433/)) and IPIP (IP in IP).

[udp-tunnel.sh](udp-tunnel.sh) is a simple bash script to set up a network-layer point-to-point tunnel using the Linux kernel modules FOU ([foo-over-udp](https://lwn.net/Articles/614433/)) and IPIP (IP in IP) on a virtual TUN device. This is useful for exchanging IPv4 packets between two machines or networks across a link that is only capable of carrying UDP payloads.

The script [udp-tunnel-socat.sh](udp-tunnel-socat.sh) achieves essentially the same functionality in userspace using the network utility `socat`. This is useful where the Kernel modules are not available and high performance is not required. Also, the script creates only a temporary TUN device which is automatically removed on exit once SIGINT is received. This script is referred to throughout this document as “socat variant”.

You may find further information on how to use these scripts in the [udp-tunnel README](udp-tunnel.README.md). e.g. how to set up bi-directional tunnels to exchange arbitrary IP packets in UDP payloads.

Use at your own risk!
