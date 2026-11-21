# Module 0.2, building images. Functions for task.sh: setup_0_2_N, check_0_2_N, solve_0_2_N.

# The course registry from module 0.2, step 6, started when it isn't running yet.
registry_up() {
  if [ "$(field course-registry '{{.State.Status}}')" != running ]; then
    gone c course-registry
    local net=""
    docker network inspect k8s-lab-toolbox_default >/dev/null 2>&1 && net="--network k8s-lab-toolbox_default"
    docker run -d --name course-registry $net -p 127.0.0.1:5555:5000 registry:3.1.2 >/dev/null
  fi
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    docker run --rm --net=host alpine:3.22.2 wget -q -O /dev/null http://127.0.0.1:5555/v2/ 2>/dev/null && return 0
    sleep 1
  done
  return 1
}
# The digest the registry holds for a tag, read on the Docker host: registry_digest task-app stable
registry_digest() {
  docker run --rm --net=host alpine:3.22.2 wget -S --spider \
    --header 'Accept: application/vnd.oci.image.index.v1+json' \
    "http://127.0.0.1:5555/v2/$1/manifests/$2" 2>&1 | tr -d '\r' | awk -F': ' 'tolower($1) ~ /docker-content-digest/ {print $2}'
}

# ---- Task 1: order a Dockerfile for the cache ---------------------------------------------
setup_0_2_1() {
  local d; d="$(taskdir 0.2.1)"
  gone i course/task-cache:1
  cat > "$W/task-0.2.1/Dockerfile" <<'EOF'
FROM alpine:3.22.2
LABEL lab.course=docker
COPY . /app
RUN apk add --no-cache curl
CMD ["sh", "/app/report.sh"]
EOF
  cat > "$W/task-0.2.1/report.sh" <<'EOF'
echo "report from $(hostname) with $(curl --version | head -1 | cut -d' ' -f1,2)"
EOF
  ls -l "$d"
}
check_0_2_1() {
  local c="$W/task-0.2.1.check" out id
  check "image course/task-cache:1 exists" docker image inspect course/task-cache:1
  check_sh "it runs report.sh with curl installed" "docker run --rm course/task-cache:1 | grep -q 'report from .* with curl'"
  rm -rf "$c"; cp -R "$W/task-0.2.1" "$c"
  docker build -q -t course/task-cache:check "$c" >/dev/null 2>&1
  echo "# changed" >> "$c/report.sh"
  out="$(docker build --progress=plain -t course/task-cache:check "$c" 2>&1)"
  id="$(echo "$out" | awk '/RUN apk add/ {print $1; exit}')"
  check "after a change to report.sh, the apk add step comes from the cache" test -n "$id" -a -n "$(echo "$out" | grep -x "$id CACHED")"
  gone i course/task-cache:check; rm -rf "$c"
}
solve_0_2_1() {
  shown <<'EOF'
cat platform-engineering/0-docker/work/task-0.2.1/Dockerfile
printf 'FROM alpine:3.22.2\nLABEL lab.course=docker\nRUN apk add --no-cache curl\nCOPY . /app\nCMD ["sh", "/app/report.sh"]\n' > platform-engineering/0-docker/work/task-0.2.1/Dockerfile
docker build -q -t course/task-cache:1 platform-engineering/0-docker/work/task-0.2.1
EOF
}

# ---- Task 2: make an image small and non-root ---------------------------------------------
setup_0_2_2() {
  local d; d="$(taskdir 0.2.2)"
  gone i course/task-small:1
  cp "$DT/lab/app/main.go" "$DT/lab/app/go.mod" "$DT/lab/app/.dockerignore" "$W/task-0.2.2/"
  cp "$DT/lab/app/Dockerfile.single" "$W/task-0.2.2/Dockerfile"
  ls -lA "$d"
}
check_0_2_2() {
  local size user
  check "image course/task-small:1 exists" docker image inspect course/task-small:1
  size="$(docker image inspect -f '{{.Size}}' course/task-small:1 2>/dev/null)"
  check "it is under 20 MB ($(( ${size:-0} / 1000000 )) MB)" test "${size:-999999999}" -lt 20000000
  user="$(docker image inspect -f '{{.Config.User}}' course/task-small:1 2>/dev/null)"
  check "it runs as a non-root user (User is '$user')" test -n "$user" -a "${user%%:*}" != 0 -a "${user%%:*}" != root
  gone c course-task-small-check
  docker run -d --name course-task-small-check -p 8892:8000 course/task-small:1 >/dev/null 2>&1
  check "a container from it answers ok on /healthz" test "$(http_body 8892 /healthz)" = ok
  gone c course-task-small-check
}
solve_0_2_2() {
  shown <<'EOF'
cp platform-engineering/0-docker/lab/app/Dockerfile platform-engineering/0-docker/work/task-0.2.2/Dockerfile
docker build -q -t course/task-small:1 platform-engineering/0-docker/work/task-0.2.2
docker image ls course/task-small
EOF
}

# ---- Task 3: pin an image by digest -------------------------------------------------------
setup_0_2_3() {
  local d; d="$(taskdir 0.2.3)"
  gone c course-task-pinned
  registry_up || { echo "the registry course-registry did not start"; return 1; }
  printf 'FROM busybox:1.37.0\nLABEL lab.course=docker\nCMD ["sh", "-c", "echo build %s; sleep 3600"]\n' "$(date +%s)" \
    | docker build -q -t localhost:5555/task-app:stable - >/dev/null
  docker push -q localhost:5555/task-app:stable >/dev/null
  docker image rm localhost:5555/task-app:stable >/dev/null 2>&1
  echo "The registry localhost:5555 holds task-app:stable. Write to $d/digest.txt."
}
check_0_2_3() {
  local want got img
  want="$(registry_digest task-app stable)"
  got="$(cat "$W/task-0.2.3/digest.txt" 2>/dev/null | tr -d ' \n')"
  check "digest.txt holds the digest of task-app:stable" test -n "$want" -a "$got" = "$want"
  img="$(field course-task-pinned '{{.Config.Image}}')"
  check "course-task-pinned runs" test "$(field course-task-pinned '{{.State.Status}}')" = running
  check "course-task-pinned names its image by that digest ($img)" test -n "$want" -a "${img##*@}" = "$want"
}
solve_0_2_3() {
  shown <<'EOF'
docker pull -q localhost:5555/task-app:stable
D=$(docker image inspect -f '{{index .RepoDigests 0}}' localhost:5555/task-app:stable); echo $D
echo ${D#*@} > platform-engineering/0-docker/work/task-0.2.3/digest.txt
docker run -d --name course-task-pinned $D
EOF
}
