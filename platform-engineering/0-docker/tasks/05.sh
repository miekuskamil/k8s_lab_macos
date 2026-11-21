# Module 0.5, networking in depth. Functions for task.sh: setup_0_5_N, check_0_5_N, solve_0_5_N.

# The debug image of module 0.5, built when it's missing.
nettools() { docker image inspect course/nettools:1.0 >/dev/null 2>&1 || docker build -q -t course/nettools:1.0 "$DT/lab/nettools" >/dev/null; }
host_sh() { docker run --rm --privileged --net=host --pid=host course/nettools:1.0 sh -c "$1" 2>/dev/null; }

# ---- Task 1: a front-end and a back-end network -------------------------------------------
setup_0_5_1() {
  gone c course-task-db course-task-app course-task-edge
  gone n course-task-front course-task-back
  echo "No task containers or networks exist yet."
}
nets_of() { field "$1" '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'; }
check_0_5_1() {
  check "course-task-db runs redis on course-task-back only" test "$(field course-task-db '{{.Config.Image}}') $(nets_of course-task-db)" = "redis:8.2.2-alpine course-task-back "
  check "course-task-app is on both networks" test "$(nets_of course-task-app)" = "course-task-back course-task-front "
  check "course-task-edge is on course-task-front only" test "$(nets_of course-task-edge)" = "course-task-front "
  check_sh "the app resolves course-task-db and reaches its port 6379" "docker exec course-task-app nc -z -w 3 course-task-db 6379"
  check_sh "the edge container does not resolve course-task-db" "! docker exec course-task-edge getent hosts course-task-db >/dev/null 2>&1"
}
solve_0_5_1() {
  shown <<'EOF'
docker network create course-task-front
docker network create course-task-back
docker run -d --name course-task-db --network course-task-back redis:8.2.2-alpine
docker run -d --name course-task-app --network course-task-back alpine:3.22.2 sleep 3600
docker network connect course-task-front course-task-app
docker run -d --name course-task-edge --network course-task-front alpine:3.22.2 sleep 3600
docker exec course-task-app getent hosts course-task-db
EOF
}

# ---- Task 2: find a container's veth and its traffic --------------------------------------
setup_0_5_2() {
  taskdir 0.5.2 >/dev/null
  nettools
  gone c course-task-talker course-task-target
  gone n course-task-net
  docker network create --subnet 10.231.0.0/24 course-task-net >/dev/null
  docker run -d --name course-task-target --network course-task-net --ip 10.231.0.$(( (RANDOM % 200) + 20 )) nginx:1.28.0-alpine >/dev/null
  local ip; ip="$(docker inspect -f '{{(index .NetworkSettings.Networks "course-task-net").IPAddress}}' course-task-target)"
  docker run -d --name course-task-talker --network course-task-net alpine:3.22.2 \
    sh -c "while true; do wget -qO /dev/null -T 1 http://$ip/ 2>/dev/null; sleep 1; done" >/dev/null
  echo "course-task-talker runs. Write to platform-engineering/0-docker/work/task-0.5.2/veth.txt and target.txt."
}
check_0_5_2() {
  local idx want ip
  idx="$(docker exec course-task-talker cat /sys/class/net/eth0/iflink 2>/dev/null)"
  want="$(host_sh "ip -o link" | awk -F': ' -v i="$idx" '$1==i {print $2}' | cut -d@ -f1)"
  ip="$(docker inspect -f '{{(index .NetworkSettings.Networks "course-task-net").IPAddress}}' course-task-target 2>/dev/null)"
  check "veth.txt names the host end of the talker's veth pair ($want)" test -n "$want" -a "$(cat "$W/task-0.5.2/veth.txt" 2>/dev/null | tr -d ' \n')" = "$want"
  check "target.txt holds the address it calls" test -n "$ip" -a "$(cat "$W/task-0.5.2/target.txt" 2>/dev/null | tr -d ' \n')" = "$ip"
}
solve_0_5_2() {
  shown <<'EOF'
onhost() { docker run --rm --privileged --net=host --pid=host course/nettools:1.0 "$@"; }
IDX=$(docker exec course-task-talker cat /sys/class/net/eth0/iflink)
V=$(onhost ip -o link | awk -F': ' -v i="$IDX" '$1==i {print $2}' | cut -d@ -f1); echo $V
echo $V > platform-engineering/0-docker/work/task-0.5.2/veth.txt
onhost timeout 5 tcpdump -lnni $V -c 1 'tcp[tcpflags] & tcp-syn != 0' 2>/dev/null
onhost timeout 5 tcpdump -lnni $V -c 1 'tcp[tcpflags] & tcp-syn != 0' 2>/dev/null | awk '{print $5}' | cut -d. -f1-4 > platform-engineering/0-docker/work/task-0.5.2/target.txt
EOF
}

# ---- Task 3: publish a port on the loopback address only ----------------------------------
setup_0_5_3() {
  taskdir 0.5.3 >/dev/null
  nettools
  gone c course-task-admin
  echo "No container course-task-admin exists. Port 8896 is free for it."
}
check_0_5_3() {
  local ip
  check "course-task-admin publishes 80 on 127.0.0.1:8896 only" test "$(field course-task-admin '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}}={{.HostIp}}:{{.HostPort}} {{end}}{{end}}')" = "80/tcp=127.0.0.1:8896 "
  ip="$(field course-task-admin '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
  check "the DNAT rule matches only 127.0.0.1" test -n "$(host_sh "iptables -t nat -S DOCKER" | grep -- '--dport 8896' | grep -- '-d 127.0.0.1/32')"
  check "dnat.txt holds the rule's destination ($ip:80)" test -n "$ip" -a "$(cat "$W/task-0.5.3/dnat.txt" 2>/dev/null | tr -d ' \n')" = "$ip:80"
}
solve_0_5_3() {
  shown <<'EOF'
onhost() { docker run --rm --privileged --net=host --pid=host course/nettools:1.0 "$@"; }
docker run -d --name course-task-admin -p 127.0.0.1:8896:80 nginx:1.28.0-alpine
onhost iptables -t nat -S DOCKER | grep 8896
onhost iptables -t nat -S DOCKER | grep 8896 | sed 's/.*--to-destination //' > platform-engineering/0-docker/work/task-0.5.3/dnat.txt
EOF
}
