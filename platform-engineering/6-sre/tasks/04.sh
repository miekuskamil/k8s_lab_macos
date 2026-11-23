# Module 6.4, backup and disaster recovery. Functions for task.sh: setup_6_4_N, check_6_4_N, solve_6_4_N.

velero6() { "${K[@]}" -n velero exec "$("${K[@]}" -n velero get pod -l name=velero -o name 2>/dev/null)" -c velero -- /velero "$@" 2>/dev/null; }
sql6() { "${K[@]}" -n "$1" exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "$2" 2>/dev/null; }

# The module's stack: SeaweedFS with the bucket, CloudNativePG, Velero and the orders database.
backup_stack() {
  echo "Installing the object store, CloudNativePG and Velero, if missing (about 3 minutes)"
  "${K[@]}" apply -f "$M/6.4-object-store.yaml" >/dev/null
  "${K[@]}" -n course-backup rollout status deploy/seaweedfs --timeout=300s >/dev/null 2>&1
  "${K[@]}" -n course-backup exec deploy/seaweedfs -- sh -c 'echo "s3.bucket.create -name velero" | weed shell' >/dev/null 2>&1
  "${H[@]}" status cnpg -n cnpg-system >/dev/null 2>&1 || "${H[@]}" upgrade --install cnpg cloudnative-pg --repo https://cloudnative-pg.github.io/charts \
    --version 0.29.1 -n cnpg-system --create-namespace -f "$M/6.4-cnpg-values.yaml" --wait --timeout 5m >/dev/null
  "${H[@]}" status velero -n velero >/dev/null 2>&1 || "${H[@]}" upgrade --install velero velero --repo https://vmware-tanzu.github.io/helm-charts \
    --version 12.2.2 -n velero --create-namespace -f "$M/6.4-velero-values.yaml" --wait --timeout 6m >/dev/null
  bsl() { [ "$("${K[@]}" -n velero get backupstoragelocation default -o jsonpath='{.status.phase}' 2>/dev/null)" = Available ]; }
  poll 120 bsl
  "${K[@]}" apply -f "$M/6.4-orders-db.yaml" >/dev/null
  "${K[@]}" -n course-dr wait --for=condition=Ready cluster/orders-db --timeout=300s >/dev/null 2>&1
  sql6 course-dr "CREATE TABLE IF NOT EXISTS orders (id serial PRIMARY KEY, item text, placed timestamptz DEFAULT now());" >/dev/null
}

# ---- Task 1: a nightly backup schedule ----------------------------------------------------
setup_6_4_1() {
  backup_stack
  "${K[@]}" -n velero delete schedules.velero.io orders-nightly --ignore-not-found >/dev/null
  echo "Velero runs and the orders database lives in course-dr. No schedule named orders-nightly exists."
}
check_6_4_1() {
  local s
  s="$("${K[@]}" -n velero get schedules.velero.io orders-nightly -o json 2>/dev/null | python3 -c 'import json,sys
s = json.load(sys.stdin)["spec"]; t = s["template"]
print(s["schedule"], ",".join(t.get("includedNamespaces", [])), t.get("ttl", ""), t.get("defaultVolumesToFsBackup", False), sep="|")' 2>/dev/null)"
  check "Schedule velero/orders-nightly exists" test -n "$s"
  check "it runs every day at 02:00" matches "$s" '^0 2 \* \* \*\|'
  check "it backs up only course-dr" matches "$s" '\|course-dr\|'
  check "it keeps each backup for 7 days" matches "$s" '\|168h0m0s\|'
  check "it copies volumes with the file system backup" matches "$s" '\|True$'
  check "Velero accepted it (phase Enabled)" matches "$("${K[@]}" -n velero get schedules.velero.io orders-nightly -o jsonpath='{.status.phase}' 2>/dev/null)" '^Enabled$'
}
solve_6_4_1() {
  shown <<'EOF'
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero -o name)" -c velero -- /velero schedule create orders-nightly --schedule="0 2 * * *" --include-namespaces course-dr --ttl 168h --default-volumes-to-fs-backup
kubectl -n velero get schedules.velero.io orders-nightly
EOF
}

# ---- Task 2: a restore drill, and the data you lose ---------------------------------------
setup_6_4_2() {
  local n
  backup_stack
  "${K[@]}" delete namespace course-dr-drill --ignore-not-found --wait=true --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n velero delete restores.velero.io --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1
  velero6 backup delete task-6-4-2 --confirm >/dev/null
  gone() { ! "${K[@]}" -n velero get backups.velero.io task-6-4-2 >/dev/null 2>&1; }
  poll 60 gone
  sql6 course-dr "INSERT INTO orders (item) SELECT 'task-' || g FROM generate_series(1, 100) g;" >/dev/null
  n="$(sql6 course-dr 'SELECT count(*) FROM orders')"
  velero6 backup create task-6-4-2 --include-namespaces course-dr --default-volumes-to-fs-backup --wait >/dev/null
  sql6 course-dr "INSERT INTO orders (item) SELECT 'after-' || g FROM generate_series(1, 7) g;" >/dev/null
  "${K[@]}" -n course-dr create configmap task-6-4-2 --dry-run=client -o yaml \
    --from-literal=in-backup="$n" --from-literal=now="$(sql6 course-dr 'SELECT count(*) FROM orders')" | "${K[@]}" apply -f - >/dev/null
  echo "The backup task-6-4-2 holds $n orders. 7 more arrived after it."
  echo "Prove the backup works: restore it into course-dr-drill without touching course-dr (task 6.4.2)."
}
check_6_4_2() {
  local want now drill orig
  want="$("${K[@]}" -n course-dr get configmap task-6-4-2 -o jsonpath='{.data.in-backup}' 2>/dev/null)"
  now="$("${K[@]}" -n course-dr get configmap task-6-4-2 -o jsonpath='{.data.now}' 2>/dev/null)"
  local restored
  restored="$("${K[@]}" -n velero get restores.velero.io -o jsonpath='{range .items[*]}{.spec.backupName} {.status.phase}{"\n"}{end}' 2>/dev/null)"
  check "a restore from task-6-4-2 completed" matches "$restored" 'task-6-4-2 Completed'
  ready() { [ "$("${K[@]}" -n course-dr-drill get cluster orders-db -o jsonpath='{.status.phase}' 2>/dev/null)" = "Cluster in healthy state" ]; }
  # The operator needs up to a minute after the restore; without a restore there is nothing to wait for.
  if matches "$restored" 'task-6-4-2 Completed'; then poll 240 ready; fi
  check "the drill database in course-dr-drill is healthy" ready
  drill="$(sql6 course-dr-drill 'SELECT count(*) FROM orders')"
  check "it holds the $want orders of the backup (got ${drill:-none})" test "$drill" = "$want"
  orig="$(sql6 course-dr 'SELECT count(*) FROM orders')"
  check "the original in course-dr still holds all $now orders (got ${orig:-none})" test "$orig" = "$now"
}
solve_6_4_2() {
  shown <<'EOF'
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero -o name)" -c velero -- /velero restore create --from-backup task-6-4-2 --namespace-mappings course-dr:course-dr-drill --wait
kubectl -n course-dr-drill wait --for=condition=Ready cluster/orders-db --timeout=300s
kubectl -n course-dr-drill exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc 'SELECT count(*) FROM orders'
EOF
}
