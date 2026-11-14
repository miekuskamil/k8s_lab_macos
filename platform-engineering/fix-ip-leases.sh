#!/usr/bin/env bash
# Module 21: free pod IPs that leaked while the CNI was broken.
# flannel's host-local IPAM keeps one file per handed-out IP in /var/lib/cni/networks/cbr0.
# When pod sandboxes fail half-way, those files stay behind until all 254 addresses are
# "in use" and no new pod gets an IP. This deletes only files for IPs that no pod holds.
set -euo pipefail
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
NODE="k3d-${CLUSTER_NAME:-k8s-lab}-server-0"
DIR=/var/lib/cni/networks/cbr0
used="$("${K[@]}" get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | grep '^10\.42\.' | sort -u | paste -sd'|' -)"
before="$(docker exec "$NODE" sh -c "ls $DIR | grep -c '^10\\.42\\.'")"
docker exec "$NODE" sh -c "cd $DIR && for f in 10.42.*; do echo \"\$f\" | grep -qxE '${used:-none}' || rm -f \"\$f\"; done"
after="$(docker exec "$NODE" sh -c "ls $DIR | grep -c '^10\\.42\\.'")"
echo "IP leases on $NODE: $before before, $after after (pods hold $(echo "$used" | tr '|' '\n' | grep -c .))"
