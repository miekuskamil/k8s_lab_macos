# Module 0.3, Docker Compose. Functions for task.sh: setup_0_3_N, check_0_3_N, solve_0_3_N.

# ---- Task 1: wait for a healthy database --------------------------------------------------
setup_0_3_1() {
  local d; d="$(taskdir 0.3.1)"
  gone p course-task-compose
  docker build -q -t course/hits:task "$DT/lab/app" >/dev/null
  cat > "$W/task-0.3.1/compose.yaml" <<'EOF'
name: course-task-compose

services:
  app:
    image: course/hits:task
    environment:
      REDIS_ADDR: redis:6379
    depends_on:
      - redis

  redis:
    image: redis:8.2.2-alpine
EOF
  cat > "$W/task-0.3.1/solution.yaml" <<'EOF'
name: course-task-compose

services:
  app:
    image: course/hits:task
    environment:
      REDIS_ADDR: redis:6379
    ports:
      - "8893:8000"
    depends_on:
      redis:
        condition: service_healthy

  redis:
    image: redis:8.2.2-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 2s
      retries: 5
EOF
  echo "Edit $d/compose.yaml, then start it with docker compose -f $d/compose.yaml up -d"
}
check_0_3_1() {
  check "redis of course-task-compose runs and is healthy" test "$(field course-task-compose-redis-1 '{{.State.Health.Status}}')" = healthy
  check "its healthcheck runs redis-cli ping" test -n "$(field course-task-compose-redis-1 '{{json .Config.Healthcheck.Test}}' | grep 'redis-cli' | grep ping)"
  check "app waits for redis to be healthy" test -n "$(field course-task-compose-app-1 '{{index .Config.Labels "com.docker.compose.depends_on"}}' | grep 'redis:service_healthy')"
  check "port 8893 answers with the shared counter" test -n "$(http_body 8893 / | grep 'visit [0-9]')"
}
solve_0_3_1() {
  shown <<'EOF'
cp platform-engineering/0-docker/work/task-0.3.1/solution.yaml platform-engineering/0-docker/work/task-0.3.1/compose.yaml
cat platform-engineering/0-docker/work/task-0.3.1/compose.yaml
docker compose -f platform-engineering/0-docker/work/task-0.3.1/compose.yaml up -d --wait 2>&1 | tail -3
EOF
}

# ---- Task 2: three copies behind the proxy ------------------------------------------------
setup_0_3_2() {
  gone p course-compose
  mkdir -p "$W"; rm -rf "$W/compose" "$W/app"
  cp -R "$DT/lab/app" "$DT/lab/compose" "$W/"
  docker compose -f "$W/compose/compose.yaml" up -d --build --wait >/dev/null 2>&1
  docker compose -f "$W/compose/compose.yaml" ps --format '{{.Name}} {{.Status}}'
}
check_0_3_2() {
  local names
  check "three api containers of course-compose run" test "$(docker ps -q --filter label=com.docker.compose.project=course-compose --filter label=com.docker.compose.service=api | wc -l | tr -d ' ')" = 3
  check "compose.yaml still names one api service with no replicas setting" test -z "$(grep -E 'replicas|scale' "$W/compose/compose.yaml")"
  sleep 6
  names="$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do http_body 8884 /; done | awk '{print $3}' | sort -u | wc -l | tr -d ' ')"
  check "requests through the proxy reach all three ($names different hostnames)" test "$names" = 3
}
solve_0_3_2() {
  shown <<'EOF'
docker compose -f platform-engineering/0-docker/work/compose/compose.yaml up -d --scale api=3 --wait 2>&1 | tail -1
sleep 6; for i in $(seq 1 9); do curl -s http://host.docker.internal:8884/ || curl -s http://localhost:8884/; done | awk '{print $3}' | sort | uniq -c
EOF
}

# ---- Task 3: keep a tool out of the default start -----------------------------------------
setup_0_3_3() {
  local d; d="$(taskdir 0.3.3)"
  gone p course-task-profiles
  cat > "$W/task-0.3.3/compose.yaml" <<'EOF'
name: course-task-profiles

services:
  web:
    image: nginx:1.28.0-alpine
    ports:
      - "8895:80"

  tools:
    image: alpine:3.22.2
    command: ["sleep", "infinity"]
EOF
  cat > "$W/task-0.3.3/solution.yaml" <<'EOF'
name: course-task-profiles

services:
  web:
    image: nginx:1.28.0-alpine
    ports:
      - "${WEB_PORT}:80"

  tools:
    image: alpine:3.22.2
    profiles: [debug]
    command: ["sleep", "infinity"]
EOF
  echo "Edit $d/compose.yaml and add $d/.env, then start the project."
}
check_0_3_3() {
  local f="$W/task-0.3.3/compose.yaml"
  check "without a profile, the project lists only web" test "$(docker compose -f "$f" config --services 2>/dev/null | tr '\n' ' ')" = "web "
  check "with --profile debug, it lists tools too" test -n "$(docker compose -f "$f" --profile debug config --services 2>/dev/null | grep -x tools)"
  check ".env sets WEB_PORT=8894" grep -qx 'WEB_PORT=8894' "$W/task-0.3.3/.env"
  check "compose.yaml reads the port from WEB_PORT" grep -q 'WEB_PORT' "$f"
  check "web runs and answers on port 8894" test "$(http_code 8894 /)" = 200
  check "no tools container runs" test -z "$(docker ps -q --filter label=com.docker.compose.project=course-task-profiles --filter label=com.docker.compose.service=tools)"
}
solve_0_3_3() {
  shown <<'EOF'
docker compose -f platform-engineering/0-docker/work/task-0.3.3/compose.yaml down --remove-orphans 2>&1 | tail -1
cp platform-engineering/0-docker/work/task-0.3.3/solution.yaml platform-engineering/0-docker/work/task-0.3.3/compose.yaml
echo WEB_PORT=8894 > platform-engineering/0-docker/work/task-0.3.3/.env
docker compose -f platform-engineering/0-docker/work/task-0.3.3/compose.yaml up -d --wait 2>&1 | tail -1
docker compose -f platform-engineering/0-docker/work/task-0.3.3/compose.yaml config --services
EOF
}
