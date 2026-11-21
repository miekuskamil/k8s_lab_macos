# The Docker track's debug image: the Linux network tools that modules 0.5 to 0.7 run on the
# Docker host. Started with --privileged --net=host --pid=host, it sees the host's interfaces,
# bridges, firewall rules and processes, on a Mac (OrbStack's VM) and on Linux alike.
#   iproute2        ip, ss and bridge
#   iptables        iptables with the nf_tables backend, the one Docker uses
#   nftables        nft, to read the same rules as nftables
#   tcpdump         packet captures
#   conntrack-tools conntrack, the kernel's table of connections and their NAT
#   util-linux      nsenter, to run a command in a container's network namespace
#   curl, bind-tools, libcap-utils   curl, dig, capsh
FROM alpine:3.22.2
LABEL lab.course="docker"
RUN apk add --no-cache iproute2 iptables nftables tcpdump conntrack-tools util-linux \
      curl bind-tools libcap-utils
