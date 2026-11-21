# Module 0.7, debugging. Functions for task.sh: setup_0_7_N, check_0_7_N, solve_0_7_N.

# ---- Task 1: repair a project that never comes up -----------------------------------------
setup_0_7_1() {
  local d; d="$(taskdir 0.7.1)"
  gone p course-task-broken
  rm -rf "$W/app"; mkdir -p "$W"; cp -R "$DT/lab/app" "$W/app"
  cp "$DT/lab/compose/nginx.conf" "$W/task-0.7.1/nginx.conf"
  cat > "$W/task-0.7.1/compose.yaml" <<'EOF'
name: course-task-broken

services:
  proxy:
    image: nginx:1.28.0-alpine
    restart: on-failure
    ports:
      - "8898:80"
    volumes:
      - ./site.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      api:
        condition: service_healthy

  api:
    build: ../app
    image: course/hits:task
    environment:
      REDIS_ADDR: redis:6379
    depends_on:
      redis:
        condition: service_healthy

  redis:
    image: redis:8.2.2-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "pong"]
      interval: 2s
      timeout: 2s
      retries: 3
EOF
  docker compose -f "$W/task-0.7.1/compose.yaml" up -d --build >/dev/null 2>&1
  echo "Project course-task-broken started from $d. Port 8898 doesn't answer."
}
check_0_7_1() {
  check "redis of course-task-broken is healthy" test "$(field course-task-broken-redis-1 '{{.State.Health.Status}}')" = healthy
  check "the api runs and is healthy" test "$(field course-task-broken-api-1 '{{.State.Health.Status}}')" = healthy
  check "the proxy runs without restarts since its last start" test "$(field course-task-broken-proxy-1 '{{.State.Status}}')" = running
  check "port 8898 answers with a visit counter" test -n "$(http_body 8898 / | grep 'visit [0-9]')"
}
solve_0_7_1() {
  shown <<'EOF'
docker compose -f platform-engineering/0-docker/work/task-0.7.1/compose.yaml ps -a --format '{{.Service}} {{.Status}}'
perl -pi -e 's/"redis-cli", "pong"/"redis-cli", "ping"/; s#\./site\.conf:#./nginx.conf:#' platform-engineering/0-docker/work/task-0.7.1/compose.yaml
rm -rf platform-engineering/0-docker/work/task-0.7.1/site.conf
docker compose -f platform-engineering/0-docker/work/task-0.7.1/compose.yaml up -d --wait 2>&1 | tail -1
EOF
}

# ---- Task 2: find why a container keeps dying ---------------------------------------------
setup_0_7_2() {
  taskdir 0.7.2 >/dev/null
  gone c course-task-crashy
  printf 'FROM alpine:3.22.2\nLABEL lab.course=docker\nCMD ["sh", "-c", "echo starting; [ -n \\"$CONFIG_URL\\" ] || { echo \\"CONFIG_URL is not set\\" >&2; exit 4; }; echo \\"config from $CONFIG_URL\\"; while true; do sleep 5; done"]\n' \
    | docker build -q -t course/task-crashy:1 - >/dev/null
  docker run -d --name course-task-crashy --restart on-failure:5 course/task-crashy:1 >/dev/null
  echo "course-task-crashy started with --restart on-failure:5."
}
check_0_7_2() {
  check "exitcode.txt holds the exit code (4)" test "$(cat "$W/task-0.7.2/exitcode.txt" 2>/dev/null | tr -d ' \n')" = 4
  check "course-task-crashy runs course/task-crashy:1" test "$(field course-task-crashy '{{.State.Status}} {{.Config.Image}}')" = "running course/task-crashy:1"
  sleep 2
  check "it stays up" test "$(field course-task-crashy '{{.State.Status}} {{.RestartCount}}')" = "running 0"
}
solve_0_7_2() {
  shown <<'EOF'
docker inspect -f '{{.State.ExitCode}}' course-task-crashy > platform-engineering/0-docker/work/task-0.7.2/exitcode.txt
docker logs course-task-crashy 2>&1 | tail -1
docker rm -f course-task-crashy
docker run -d --name course-task-crashy -e CONFIG_URL=http://config.local/app course/task-crashy:1
EOF
}

# ---- Task 3: look inside a container without a shell --------------------------------------
setup_0_7_3() {
  taskdir 0.7.3 >/dev/null
  gone c course-task-quiet
  docker image inspect course/nettools:1.0 >/dev/null 2>&1 || docker build -q -t course/nettools:1.0 "$DT/lab/nettools" >/dev/null
  docker build -q -t course/hits:1.0.0 "$DT/lab/app" >/dev/null
  docker run -d --name course-task-quiet -e PORT=$(( (RANDOM % 900) + 9100 )) course/hits:1.0.0 >/dev/null
  echo "course-task-quiet runs. Write its port to platform-engineering/0-docker/work/task-0.7.3/port.txt."
}
check_0_7_3() {
  local want; want="$(field course-task-quiet '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^PORT=//p')"
  check "course-task-quiet still runs its first start" test "$(field course-task-quiet '{{.State.Status}} {{.RestartCount}}')" = "running 0"
  check "port.txt holds the port it listens on" test -n "$want" -a "$(cat "$W/task-0.7.3/port.txt" 2>/dev/null | tr -d ' \n')" = "$want"
}
solve_0_7_3() {
  shown <<'EOF'
docker run --rm --network container:course-task-quiet course/nettools:1.0 ss -ltn
docker run --rm --network container:course-task-quiet course/nettools:1.0 ss -ltnH | awk '{print $4}' | sed 's/.*://' > platform-engineering/0-docker/work/task-0.7.3/port.txt
EOF
}
