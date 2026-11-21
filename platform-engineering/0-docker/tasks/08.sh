# Module 0.8, the capstone. Functions for task.sh: setup_0_8_N, check_0_8_N, solve_0_8_N.

CAP="$W/capstone"
cap() { docker compose -f "$CAP/compose.yaml" "$@"; }
# The digest the course registry holds for a tag, asked from the Docker host.
reg_digest() {
  docker run --rm --net=host alpine:3.22.2 wget -S --spider --header 'Accept: application/vnd.oci.image.index.v1+json' \
    "http://127.0.0.1:5555/v2/$1/manifests/$2" 2>&1 | tr -d '\r' | awk -F': ' 'tolower($1) ~ /docker-content-digest/ {print $2}'
}
# The capstone of module 0.8 up to step 3, without the signatures: images built and pushed,
# digests pinned in .env, the project running.
capstone_up() {
  gone p course-capstone
  mkdir -p "$W"; rm -rf "$CAP"; cp -R "$DT/lab/capstone" "$CAP"
  docker build -q --build-arg VERSION=2.0.0 --build-arg GO_IMAGE=golang:1.27.3-alpine3.24 -t localhost:5555/hits:2.0.0 "$DT/lab/app" >/dev/null
  docker build -q -t localhost:5555/proxy:1.0.0 "$CAP/proxy" >/dev/null
  registry_up || return 1
  docker push -q localhost:5555/hits:2.0.0 >/dev/null && docker push -q localhost:5555/proxy:1.0.0 >/dev/null
  printf 'API_IMAGE=localhost:5555/hits@%s\nPROXY_IMAGE=localhost:5555/proxy@%s\n' "$(reg_digest hits 2.0.0)" "$(reg_digest proxy 1.0.0)" > "$CAP/.env"
  cap up -d --wait >/dev/null 2>&1
}
hardened() {  # hardened <container>: read-only, no capabilities, no-new-privileges, not root
  local c="$1" u
  u="$(field "$c" '{{.Config.User}}')"
  [ "$(field "$c" '{{.HostConfig.ReadonlyRootfs}}')" = true ] &&
  field "$c" '{{json .HostConfig.CapDrop}}' | grep -qi '"all"' &&
  [ "$(field "$c" '{{json .HostConfig.CapAdd}}')" = null ] &&
  field "$c" '{{json .HostConfig.SecurityOpt}}' | grep -q 'no-new-privileges' &&
  [ -n "$u" ] && [ "${u%%:*}" != 0 ] && [ "${u%%:*}" != root ]
}

# ---- Task 1: add a hardened worker --------------------------------------------------------
setup_0_8_1() {
  capstone_up || { echo "the capstone did not start"; return 1; }
  # An override file can't use the main file's anchor, so the solution spells the settings out.
  cat > "$CAP/worker.yaml" <<'EOF'
services:
  worker:
    image: alpine:3.22.2
    user: "1000:1000"
    command: ["sleep", "3600"]
    read_only: true
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    restart: unless-stopped
    networks: [back]
    mem_limit: 32m
EOF
  cap ps --format '{{.Service}} {{.Status}}'
}
check_0_8_1() {
  local c=course-capstone-worker-1
  check "the worker runs alpine:3.22.2 sleep 3600" test "$(field $c '{{.State.Status}} {{.Config.Image}} {{json .Config.Cmd}}')" = 'running alpine:3.22.2 ["sleep","3600"]'
  check "it runs as 1000:1000" test "$(field $c '{{.Config.User}}')" = 1000:1000
  check "it is hardened like the others" hardened $c
  check "it sits on the back network only" test "$(field $c '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')" = "course-capstone_back "
  check "its memory limit is 32 MiB" test "$(field $c '{{.HostConfig.Memory}}')" = 33554432
}
solve_0_8_1() {
  shown <<'EOF'
cat platform-engineering/0-docker/work/capstone/worker.yaml
docker compose -f platform-engineering/0-docker/work/capstone/compose.yaml -f platform-engineering/0-docker/work/capstone/worker.yaml up -d worker 2>&1 | tail -1
EOF
}

# ---- Task 2: find the gap -----------------------------------------------------------------
setup_0_8_2() {
  capstone_up || { echo "the capstone did not start"; return 1; }
  # Weaken the api and redis, the way a hurried fix would.
  perl -0pi -e 's/  api:\n    <<: \*hardened\n/  api:\n    <<: *hardened\n    read_only: false\n    cap_add: [NET_RAW]\n    user: "0"\n/; s/    networks: \[back\]\n    mem_limit: 128m/    networks: [front, back]\n    mem_limit: 128m/' "$CAP/compose.yaml"
  cap up -d --wait >/dev/null 2>&1
  cap ps --format '{{.Service}} {{.Status}}'
}
check_0_8_2() {
  local c
  for c in proxy api redis; do check "$c is hardened" hardened course-capstone-$c-1; done
  check "redis sits on the back network only" test "$(field course-capstone-redis-1 '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')" = "course-capstone_back "
  check "port 8889 answers with a visit counter" test -n "$(http_body 8889 / | grep 'visit [0-9]')"
}
solve_0_8_2() {
  shown <<'EOF'
for c in proxy api redis; do docker inspect -f "$c user={{.Config.User}} ro={{.HostConfig.ReadonlyRootfs}} add={{.HostConfig.CapAdd}} nets={{len .NetworkSettings.Networks}}" course-capstone-$c-1; done
cp platform-engineering/0-docker/lab/capstone/compose.yaml platform-engineering/0-docker/work/capstone/compose.yaml
docker compose -f platform-engineering/0-docker/work/capstone/compose.yaml up -d --wait 2>&1 | tail -1
EOF
}

# ---- Task 3: release a new API version the safe way ---------------------------------------
setup_0_8_3() {
  if ! command -v cosign >/dev/null 2>&1; then echo "this task needs cosign: run it in the toolbox (./lab.sh shell)"; return 1; fi
  capstone_up || { echo "the capstone did not start"; return 1; }
  rm -f "$CAP/cosign.key" "$CAP/cosign.pub"
  COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix "$CAP/cosign" >/dev/null 2>&1
  echo "The capstone runs version 2.0.0. Its key pair is $CAP/cosign.key and cosign.pub."
}
check_0_8_3() {
  local d api
  if ! command -v cosign >/dev/null 2>&1; then echo "  this check runs cosign: run it in the toolbox (./lab.sh shell)"; FAILS=$((FAILS + 1)); return; fi
  d="$(reg_digest hits 2.0.1)"
  check "the registry holds hits:2.0.1" test -n "$d"
  check ".env pins hits@ that digest" grep -qx "API_IMAGE=localhost:5555/hits@$d" "$CAP/.env"
  check_sh "the digest carries a signature from the capstone's key" "cosign verify --key '$CAP/cosign.pub' --insecure-ignore-tlog 'localhost:5555/hits@$d' >/dev/null 2>&1"
  api="$(field course-capstone-api-1 '{{.Config.Image}}')"
  check "the running api uses that digest" test -n "$d" -a "${api##*@}" = "$d"
  check "the proxy answers with version 2.0.1" test -n "$(http_body 8889 / | grep 'version 2.0.1$')"
}
solve_0_8_3() {
  shown <<'EOF'
C=platform-engineering/0-docker/work/capstone
docker build -q --build-arg VERSION=2.0.1 --build-arg GO_IMAGE=golang:1.27.3-alpine3.24 -t localhost:5555/hits:2.0.1 platform-engineering/0-docker/lab/app
trivy image --quiet --scanners vuln --severity CRITICAL --exit-code 1 localhost:5555/hits:2.0.1 >/dev/null && docker push -q localhost:5555/hits:2.0.1
D=$(curl -s -I -H 'Accept: application/vnd.oci.image.index.v1+json' http://localhost:5555/v2/hits/manifests/2.0.1 | tr -d '\r' | awk '/Docker-Content-Digest/ {print $2}')
COSIGN_PASSWORD= cosign sign --yes --key $C/cosign.key --use-signing-config=false --tlog-upload=false localhost:5555/hits@$D 2>&1 | grep Pushing
perl -pi -e "s#^API_IMAGE=.*#API_IMAGE=localhost:5555/hits\@$D#" $C/.env
docker compose -f $C/compose.yaml up -d --wait 2>&1 | tail -1
curl -s http://host.docker.internal:8889/ || curl -s http://localhost:8889/
EOF
}
