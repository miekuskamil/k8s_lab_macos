# Module 0.1, containers and images. Functions for task.sh: setup_0_1_N, check_0_1_N, solve_0_1_N.

# ---- Task 1: a web server with a port, a limit, a restart policy and a label --------------
setup_0_1_1() {
  gone c course-task-web
  echo "No container course-task-web exists. Port 8890 is free for it."
}
check_0_1_1() {
  check "course-task-web runs nginx:1.28.0-alpine" test "$(field course-task-web '{{.State.Status}} {{.Config.Image}}')" = "running nginx:1.28.0-alpine"
  check "port 8890 of the Docker host answers 200" test "$(http_code 8890 /)" = 200
  check "its memory limit is 128 MiB" test "$(field course-task-web '{{.HostConfig.Memory}}')" = 134217728
  check "its restart policy is unless-stopped" test "$(field course-task-web '{{.HostConfig.RestartPolicy.Name}}')" = unless-stopped
  check "it carries the label team=web" test "$(field course-task-web '{{index .Config.Labels "team"}}')" = web
}
solve_0_1_1() {
  shown <<'EOF'
docker rm -f course-task-web 2>/dev/null; true
docker run -d --name course-task-web -p 8890:80 --memory 128m --restart unless-stopped --label team=web nginx:1.28.0-alpine
docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.RestartPolicy.Name}} {{.Config.Labels.team}}' course-task-web
EOF
}

# ---- Task 2: rescue a file a running container wrote --------------------------------------
setup_0_1_2() {
  local d token
  d="$(taskdir 0.1.2)"
  gone c course-task-mystery
  token="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16)"
  docker run -d --name course-task-mystery --label "lab.expect=$token" alpine:3.22.2 sh -c \
    "mkdir -p /var/lib/report/$(date +%s) && echo $token > /var/lib/report/\$(ls /var/lib/report)/result.txt && sleep 3600" >/dev/null
  echo "Container course-task-mystery wrote one file somewhere after it started."
  echo "Copy that file to $d/result.txt."
}
check_0_1_2() {
  local want; want="$(field course-task-mystery '{{index .Config.Labels "lab.expect"}}')"
  check "course-task-mystery still runs" test "$(field course-task-mystery '{{.State.Status}}')" = running
  check "work/task-0.1.2/result.txt holds the file the container wrote" test -n "$want" -a "$(cat "$W/task-0.1.2/result.txt" 2>/dev/null)" = "$want"
}
solve_0_1_2() {
  shown <<'EOF'
docker diff course-task-mystery
F=$(docker diff course-task-mystery | awk '$1=="A" && /result.txt$/ {print $2}'); echo $F
docker cp course-task-mystery:$F platform-engineering/0-docker/work/task-0.1.2/result.txt
cat platform-engineering/0-docker/work/task-0.1.2/result.txt
EOF
}

# ---- Task 3: a container that takes 10 seconds to stop ------------------------------------
setup_0_1_3() {
  gone c course-task-slow
  docker run -d --name course-task-slow alpine:3.22.2 sh -c 'while true; do sleep 1; done' >/dev/null
  echo "course-task-slow runs: sh -c 'while true; do sleep 1; done'. docker stop takes 10 seconds."
}
check_0_1_3() {
  local t0 t1
  check "course-task-slow runs" test "$(field course-task-slow '{{.State.Status}}')" = running
  check "it runs the same command as before" test "$(field course-task-slow '{{json .Config.Cmd}}')" = '["sh","-c","while true; do sleep 1; done"]'
  t0=$(date +%s); docker stop course-task-slow >/dev/null 2>&1; t1=$(date +%s)
  check "docker stop takes under 3 seconds (it took $((t1 - t0)))" test $((t1 - t0)) -lt 3
  check "it stopped through SIGTERM, not SIGKILL" test "$(field course-task-slow '{{.State.ExitCode}}')" != 137
  docker start course-task-slow >/dev/null 2>&1
}
solve_0_1_3() {
  shown <<'EOF'
docker rm -f course-task-slow
docker run -d --init --name course-task-slow alpine:3.22.2 sh -c 'while true; do sleep 1; done'
docker exec course-task-slow ps
EOF
}
