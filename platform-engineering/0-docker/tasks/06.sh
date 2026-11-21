# Module 0.6, security. Functions for task.sh: setup_0_6_N, check_0_6_N, solve_0_6_N.

# ---- Task 1: harden a running container ---------------------------------------------------
setup_0_6_1() {
  gone c course-task-hard
  docker build -q --build-arg VERSION=1.0.0 -t course/hits:1.0.0 "$DT/lab/app" >/dev/null
  echo "Image course/hits:1.0.0 is ready. No container course-task-hard exists."
}
check_0_6_1() {
  check "course-task-hard runs course/hits:1.0.0" test "$(field course-task-hard '{{.State.Status}} {{.Config.Image}}')" = "running course/hits:1.0.0"
  check "its root filesystem is read-only" test "$(field course-task-hard '{{.HostConfig.ReadonlyRootfs}}')" = true
  check "it drops all capabilities" test -n "$(field course-task-hard '{{json .HostConfig.CapDrop}}' | grep -i '"all"')"
  check "it sets no-new-privileges" test -n "$(field course-task-hard '{{json .HostConfig.SecurityOpt}}' | grep 'no-new-privileges')"
  check "its memory limit is 64 MiB" test "$(field course-task-hard '{{.HostConfig.Memory}}')" = 67108864
  check "its process limit is 50" test "$(field course-task-hard '{{.HostConfig.PidsLimit}}')" = 50
  check "port 8897 answers ok on /healthz" test "$(http_body 8897 /healthz)" = ok
}
solve_0_6_1() {
  shown <<'EOF'
docker run -d --name course-task-hard --read-only --cap-drop ALL --security-opt no-new-privileges --memory 64m --pids-limit 50 -p 8897:8000 course/hits:1.0.0
curl -s --retry 5 --retry-all-errors --retry-delay 1 http://host.docker.internal:8897/healthz || curl -s --retry 5 --retry-all-errors --retry-delay 1 http://localhost:8897/healthz
EOF
}

# ---- Task 2: fail a build on critical vulnerabilities -------------------------------------
setup_0_6_2() {
  taskdir 0.6.2 >/dev/null
  docker build -q --build-arg VERSION=1.0.1 --build-arg GO_IMAGE=golang:1.27.3-alpine3.24 -t course/hits:1.0.1 "$DT/lab/app" >/dev/null
  echo "Write platform-engineering/0-docker/work/task-0.6.2/gate.sh. Run this task in the toolbox, which has trivy."
}
check_0_6_2() {
  local g="$W/task-0.6.2/gate.sh"
  if ! command -v trivy >/dev/null 2>&1; then
    echo "  this check runs trivy: run it in the toolbox (./lab.sh shell)"; FAILS=$((FAILS + 1)); return
  fi
  check "gate.sh exists and is executable" test -x "$g"
  check_sh "gate.sh nginx:1.28.0-alpine exits 1 (it has CRITICAL vulnerabilities)" "'$g' nginx:1.28.0-alpine >/dev/null 2>&1; test \$? = 1"
  check_sh "gate.sh course/hits:1.0.1 exits 0" "'$g' course/hits:1.0.1 >/dev/null 2>&1"
  check "gate.sh calls trivy" grep -q trivy "$g"
}
solve_0_6_2() {
  shown <<'EOF'
printf '#!/bin/sh\nexec trivy image --quiet --scanners vuln --severity CRITICAL --exit-code 1 "$1"\n' > platform-engineering/0-docker/work/task-0.6.2/gate.sh
chmod +x platform-engineering/0-docker/work/task-0.6.2/gate.sh
platform-engineering/0-docker/work/task-0.6.2/gate.sh nginx:1.28.0-alpine >/dev/null; echo "exit code $?"
platform-engineering/0-docker/work/task-0.6.2/gate.sh course/hits:1.0.1 >/dev/null; echo "exit code $?"
EOF
}

# ---- Task 3: a password as a Compose secret -----------------------------------------------
setup_0_6_3() {
  local d token; d="$(taskdir 0.6.3)"
  gone p course-task-secret
  token="tok-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)"
  echo "$token" > "$W/task-0.6.3/token.txt"
  cat > "$W/task-0.6.3/compose.yaml" <<EOF
name: course-task-secret

services:
  app:
    image: alpine:3.22.2
    environment:
      API_TOKEN: $token
    command: ["sleep", "3600"]
EOF
  cat > "$W/task-0.6.3/solution.yaml" <<'EOF'
name: course-task-secret

services:
  app:
    image: alpine:3.22.2
    secrets:
      - api_token
    command: ["sleep", "3600"]

secrets:
  api_token:
    file: ./token.txt
EOF
  docker compose -f "$W/task-0.6.3/compose.yaml" up -d >/dev/null 2>&1
  echo "Project course-task-secret runs from $d with the token in its environment."
}
check_0_6_3() {
  local token; token="$(cat "$W/task-0.6.3/token.txt" 2>/dev/null)"
  check "course-task-secret's app runs" test "$(field course-task-secret-app-1 '{{.State.Status}}')" = running
  check "the container's configuration holds no API_TOKEN" test -z "$(field course-task-secret-app-1 '{{json .Config.Env}}' | grep -e API_TOKEN -e "${token:-none}")"
  check "/run/secrets/api_token holds the token" test -n "$token" -a "$(docker exec course-task-secret-app-1 cat /run/secrets/api_token 2>/dev/null)" = "$token"
}
solve_0_6_3() {
  shown <<'EOF'
cp platform-engineering/0-docker/work/task-0.6.3/solution.yaml platform-engineering/0-docker/work/task-0.6.3/compose.yaml
docker compose -f platform-engineering/0-docker/work/task-0.6.3/compose.yaml up -d 2>&1 | tail -1
EOF
}
