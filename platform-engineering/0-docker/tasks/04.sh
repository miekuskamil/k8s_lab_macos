# Module 0.4, storage. Functions for task.sh: setup_0_4_N, check_0_4_N, solve_0_4_N.

# ---- Task 1: keep Redis's data across a new container -------------------------------------
setup_0_4_1() {
  gone c course-task-redis
  gone v course-task-redisdata
  echo "No container course-task-redis and no volume course-task-redisdata exist."
}
check_0_4_1() {
  local got
  check "course-task-redis runs redis:8.2.2-alpine" test "$(field course-task-redis '{{.State.Status}} {{.Config.Image}}')" = "running redis:8.2.2-alpine"
  check "/data is the named volume course-task-redisdata" test -n "$(field course-task-redis '{{range .Mounts}}{{.Type}} {{.Name}} {{.Destination}}{{println}}{{end}}' | grep -x 'volume course-task-redisdata /data')"
  check "the key course holds docker" test "$(docker exec course-task-redis redis-cli get course 2>/dev/null)" = docker
  # A new container on the same volume must find the key: the data really sits in the volume.
  docker exec course-task-redis redis-cli save >/dev/null 2>&1
  gone c course-task-redis-check
  docker run -d --name course-task-redis-check -v course-task-redisdata:/data redis:8.2.2-alpine redis-server --port 6380 >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do got="$(docker exec course-task-redis-check redis-cli -p 6380 get course 2>/dev/null)"; [ -n "$got" ] && break; sleep 1; done
  check "a new container on the same volume finds the key" test "$got" = docker
  gone c course-task-redis-check
}
solve_0_4_1() {
  shown <<'EOF'
docker run -d --name course-task-redis -v course-task-redisdata:/data redis:8.2.2-alpine
sleep 2; docker exec course-task-redis redis-cli set course docker
docker exec course-task-redis redis-cli save
EOF
}

# ---- Task 2: let a non-root app write to a fresh volume -----------------------------------
setup_0_4_2() {
  local d; d="$(taskdir 0.4.2)"
  gone c course-task-writer
  gone v course-task-out
  gone i course/task-writer:1 course/task-writer:2
  printf 'FROM alpine:3.22.2\nLABEL lab.course=docker\nUSER 1000\nCMD ["sh", "-c", "date > /data/out.txt && echo wrote /data/out.txt"]\n' > "$W/task-0.4.2/Dockerfile"
  docker build -q -t course/task-writer:1 "$W/task-0.4.2" >/dev/null
  echo "With a fresh volume, course/task-writer:1 fails:"
  docker run --rm -v course-task-probe:/data course/task-writer:1 2>&1
  gone v course-task-probe
}
check_0_4_2() {
  check "image course/task-writer:2 runs as user 1000" test "$(docker image inspect -f '{{.Config.User}}' course/task-writer:2 2>/dev/null)" = 1000
  check "course-task-writer ran course/task-writer:2 and exited 0" test "$(field course-task-writer '{{.Config.Image}} {{.State.Status}} {{.State.ExitCode}}')" = "course/task-writer:2 exited 0"
  check "the volume course-task-out holds out.txt, owned by 1000" test "$(docker run --rm -v course-task-out:/data alpine:3.22.2 stat -c %u /data/out.txt 2>/dev/null)" = 1000
  gone v course-task-probe
  check_sh "a brand-new volume works too" "docker run --rm -v course-task-probe:/data course/task-writer:2 >/dev/null 2>&1"
  gone v course-task-probe
}
solve_0_4_2() {
  shown <<'EOF'
cat platform-engineering/0-docker/work/task-0.4.2/Dockerfile
printf 'FROM alpine:3.22.2\nLABEL lab.course=docker\nRUN mkdir -p /data && chown 1000:1000 /data\nUSER 1000\nCMD ["sh", "-c", "date > /data/out.txt && echo wrote /data/out.txt"]\n' > platform-engineering/0-docker/work/task-0.4.2/Dockerfile
docker build -q -t course/task-writer:2 platform-engineering/0-docker/work/task-0.4.2
docker run --name course-task-writer -v course-task-out:/data course/task-writer:2
EOF
}

# ---- Task 3: back up a volume and restore it into another ---------------------------------
setup_0_4_3() {
  taskdir 0.4.3 >/dev/null
  gone v course-task-src course-task-copy
  docker volume create course-task-src >/dev/null
  docker run --rm -v course-task-src:/data alpine:3.22.2 sh -c \
    'mkdir -p /data/reports && for i in 1 2 3; do echo "report $i $RANDOM" > /data/reports/r$i.txt; done; echo config > /data/app.conf'
  echo "The volume course-task-src holds:"
  docker run --rm -v course-task-src:/data alpine:3.22.2 find /data -type f
}
sum_volume() { docker run --rm -v "$1":/data:ro alpine:3.22.2 sh -c 'cd /data && find . -type f | sort | xargs md5sum' 2>/dev/null; }
check_0_4_3() {
  local a b
  check "src.tgz is a gzip tar archive with app.conf" test -n "$(tar tzf "$W/task-0.4.3/src.tgz" 2>/dev/null | grep 'app.conf')"
  check "the volume course-task-copy exists" docker volume inspect course-task-copy
  a="$(sum_volume course-task-src)"; b="$(sum_volume course-task-copy)"
  check "course-task-copy holds the same files as course-task-src" test -n "$a" -a "$a" = "$b"
}
solve_0_4_3() {
  shown <<'EOF'
T="$PWD/platform-engineering/0-docker/work/task-0.4.3"
docker run --rm -v course-task-src:/data:ro -v "$T":/backup alpine:3.22.2 tar czf /backup/src.tgz -C /data .
docker run --rm -v course-task-copy:/data -v "$T":/backup:ro alpine:3.22.2 tar xzf /backup/src.tgz -C /data
EOF
}
