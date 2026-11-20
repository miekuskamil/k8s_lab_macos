# Domain 05, services and networking. Functions for task.sh: setup_5_N, check_5_N, solve_5_N.

# The worker's address, for NodePort and Ingress checks that run on cks-cp.
W1IP='$(kubectl get node cks-w1 -o jsonpath="{.status.addresses[?(@.type==\"InternalIP\")].address}")'

# A pod or Deployment that answers one word over HTTP on a port: web_pod ns name word port labels...
# With replicas > 0 it is a Deployment, with 0 a bare pod.
web_app() {
  local ns="$1" name="$2" word="$3" port="$4" n="$5"; shift 5
  local labels="" l
  for l in "$@"; do labels="$labels${labels:+, }${l%%=*}: ${l#*=}"; done
  local cmd="mkdir -p /www && echo $word > /www/index.html && exec httpd -f -p $port -h /www"
  if [ "$n" = 0 ]; then
    cp_sh "kubectl apply -f - >/dev/null" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $name, namespace: $ns, labels: {$labels}}
spec:
  containers:
  - name: web
    image: busybox:1.36
    command: ["sh", "-c", "$cmd"]
    ports: [{containerPort: $port}]
EOF
  else
    cp_sh "kubectl apply -f - >/dev/null" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: $name, namespace: $ns}
spec:
  replicas: $n
  selector: {matchLabels: {$labels}}
  template:
    metadata: {labels: {$labels}}
    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh", "-c", "$cmd"]
        ports: [{containerPort: $port}]
EOF
  fi
}
# A pod with wget for the connection tests: client_pod ns name labels...
client_pod() {
  local ns="$1" name="$2"; shift 2
  local labels="" l
  for l in "$@"; do labels="$labels${labels:+,}$l"; done
  cp_sh "kubectl -n $ns run $name --image=busybox:1.36 ${labels:+-l $labels} -- sleep 1d >/dev/null"
}
all_ready() { cp_sh "kubectl -n $1 wait pod --all --for=condition=Ready --timeout=120s >/dev/null"; }
# Does a pod reach a URL within 3 seconds: reach ns pod url
reach() { echo "kubectl -n $1 exec $2 -- wget -qO- -T 3 $3"; }

# ---- Task 1: a ClusterIP Service ---------------------------------------------------------------
setup_5_1() {
  ns_fresh svc-basic
  web_app svc-basic catalog catalog 8080 3 app=catalog
  client_pod svc-basic client
  all_ready svc-basic
  cp_sh 'kubectl -n svc-basic get deploy,pod,svc'
}
check_5_1() {
  check_json "Service catalog is a ClusterIP on port 80 to target port 8080" "kubectl -n svc-basic get svc catalog -o json" \
    's=p["spec"]; s["type"]=="ClusterIP" and s["ports"][0]["port"]==80 and str(s["ports"][0]["targetPort"])=="8080" and s["selector"]=={"app":"catalog"}'
  check_cp "the Service has 3 endpoints" "[ \$(kubectl -n svc-basic get endpointslice -l kubernetes.io/service-name=catalog -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w) = 3 ]"
  check_cp "client reaches http://catalog.svc-basic.svc.cluster.local" "$(reach svc-basic client http://catalog.svc-basic.svc.cluster.local) | grep -qx catalog"
}
solve_5_1() {
  shown <<'EOF'
k -n svc-basic expose deploy catalog --port=80 --target-port=8080
k -n svc-basic get svc,endpointslice
k -n svc-basic exec client -- wget -qO- http://catalog.svc-basic.svc.cluster.local
EOF
}

# ---- Task 2: a NodePort Service ------------------------------------------------------------------
setup_5_2() {
  ns_fresh svc-nodeport
  cp_sh 'kubectl -n svc-nodeport create deploy web --image=nginx:1.27-alpine --replicas=2 >/dev/null
    kubectl -n svc-nodeport rollout status deploy web --timeout=120s'
}
check_5_2() {
  check_json "Service web-np is a NodePort on 30100, port 80" "kubectl -n svc-nodeport get svc web-np -o json" \
    's=p["spec"]; s["type"]=="NodePort" and s["ports"][0]["nodePort"]==30100 and s["ports"][0]["port"]==80'
  check_cp "nginx answers on cks-w1's address, port 30100" "for i in \$(seq 1 15); do curl -s -m 3 http://$W1IP:30100 | grep -q 'Welcome to nginx' && exit 0; sleep 2; done; exit 1"
}
solve_5_2() {
  shown <<'EOF'
k -n svc-nodeport create service nodeport web-np --tcp=80:80 --node-port=30100 $do > /opt/ckad/5.2-svc.yaml
grep -A2 selector /opt/ckad/5.2-svc.yaml
EOF
  cp_sh "sed -i 's/app: web-np/app: web/' /opt/ckad/5.2-svc.yaml"
  shown <<'EOF'
k apply -f /opt/ckad/5.2-svc.yaml
k -n svc-nodeport get svc web-np
k -n svc-nodeport get endpointslice
k get node cks-w1 -o wide
curl -s http://$(k get node cks-w1 -o jsonpath='{.status.addresses[0].address}'):30100 | grep title
EOF
}

# ---- Task 3: one Service, two named ports ------------------------------------------------------------
setup_5_3() {
  ns_fresh svc-ports
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: svc-ports
spec:
  replicas: 2
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop}
    spec:
      containers:
      - name: shop
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www /metrics && echo shop > /www/index.html && echo 'orders_total 42' > /metrics/index.html && httpd -p 9090 -h /metrics && exec httpd -f -p 8080 -h /www"]
        ports:
        - name: http
          containerPort: 8080
        - name: metrics
          containerPort: 9090
EOF
  client_pod svc-ports client
  all_ready svc-ports
}
check_5_3() {
  check_json "Service shop has port http 80 and port metrics 9090, both by the container's port names" "kubectl -n svc-ports get svc shop -o json" \
    'ps={x["name"]:(x["port"],x["targetPort"]) for x in p["spec"]["ports"]}; ps=={"http":(80,"http"),"metrics":(9090,"metrics")}'
  check_cp "client gets 'shop' from http://shop" "$(reach svc-ports client http://shop) | grep -qx shop"
  check_cp "client gets the metrics from http://shop:9090" "$(reach svc-ports client http://shop:9090) | grep -q orders_total"
}
solve_5_3() {
  put_file /opt/ckad/5.3/svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: svc-ports
spec:
  selector:
    app: shop
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: metrics
    port: 9090
    targetPort: metrics
EOF
  shown <<'EOF'
k -n svc-ports get deploy shop -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'
k apply -f /opt/ckad/5.3/svc.yaml
k -n svc-ports get endpointslice
k -n svc-ports exec client -- wget -qO- http://shop
k -n svc-ports exec client -- wget -qO- http://shop:9090
EOF
}

# ---- Task 4: an Ingress with two paths --------------------------------------------------------------------
setup_5_4() {
  ns_fresh ing-shop
  web_app ing-shop web web 8080 1 app=web
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: ing-shop}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www/api && echo api > /www/api/index.html && echo orders > /www/api/orders && exec httpd -f -p 8080 -h /www"]
EOF
  cp_sh 'kubectl -n ing-shop expose deploy web --port=80 --target-port=8080 >/dev/null
    kubectl -n ing-shop expose deploy api --port=80 --target-port=8080 >/dev/null
    kubectl -n ing-shop rollout status deploy web --timeout=120s >/dev/null; kubectl -n ing-shop rollout status deploy api --timeout=120s >/dev/null
    kubectl get ingressclass; kubectl -n ingress-nginx get svc ingress-nginx-controller'
}
ING="curl -s -m 3 -H 'Host: shop.ckad.local' http://$W1IP:30080"
check_5_4() {
  check_json "Ingress shop uses class nginx and host shop.ckad.local" "kubectl -n ing-shop get ingress shop -o json" \
    'p["spec"]["ingressClassName"]=="nginx" and p["spec"]["rules"][0]["host"]=="shop.ckad.local"'
  check_cp "shop.ckad.local/ answers web" "for i in \$(seq 1 15); do $ING/ | grep -qx web && exit 0; sleep 2; done; exit 1"
  check_cp "shop.ckad.local/api/ answers api, /api/orders answers orders" "$ING/api/ | grep -qx api && $ING/api/orders | grep -qx orders"
  check_cp "another host gets no answer from the shop" "! curl -s -m 3 -H 'Host: other.ckad.local' http://$W1IP:30080/ | grep -qx web"
}
solve_5_4() {
  shown <<'EOF'
k -n ing-shop create ingress shop --class=nginx --rule='shop.ckad.local/=web:80' --rule='shop.ckad.local/api*=api:80'
k -n ing-shop get ingress shop -o yaml | grep -A20 '^spec:'
sleep 10
curl -s -H 'Host: shop.ckad.local' http://$(k get node cks-w1 -o jsonpath='{.status.addresses[0].address}'):30080/
curl -s -H 'Host: shop.ckad.local' http://$(k get node cks-w1 -o jsonpath='{.status.addresses[0].address}'):30080/api/orders
EOF
}

# ---- Task 5: repair an Ingress for two hosts -------------------------------------------------------------
setup_5_5() {
  ns_fresh ing-hosts
  web_app ing-hosts blog blog 8080 1 app=blog
  web_app ing-hosts docs docs 8080 1 app=docs
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: blog, namespace: ing-hosts}
spec:
  selector: {app: blog}
  ports: [{name: http, port: 80, targetPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: docs, namespace: ing-hosts}
spec:
  selector: {app: docs}
  ports: [{name: web, port: 8000, targetPort: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: sites, namespace: ing-hosts}
spec:
  ingressClassName: nginx-internal
  rules:
  - host: blog.ckad.local
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: blog, port: {number: 80}}}}
  - host: docs.ckad.local
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: docs, port: {name: http}}}}
EOF
  cp_sh "kubectl -n ing-hosts rollout status deploy blog --timeout=120s >/dev/null; kubectl -n ing-hosts rollout status deploy docs --timeout=120s >/dev/null
    kubectl -n ing-hosts get ingress,svc"
}
check_5_5() {
  check_cp "blog.ckad.local answers blog" "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: blog.ckad.local' http://$W1IP:30080/ | grep -qx blog && exit 0; sleep 2; done; exit 1"
  check_cp "docs.ckad.local answers docs" "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: docs.ckad.local' http://$W1IP:30080/ | grep -qx docs && exit 0; sleep 2; done; exit 1"
  check_cp "both Services keep their ports" \
    "kubectl -n ing-hosts get svc docs -o jsonpath='{.spec.ports[0].name}:{.spec.ports[0].port}' | grep -qx web:8000 && kubectl -n ing-hosts get svc blog -o jsonpath='{.spec.ports[0].port}' | grep -qx 80"
}
solve_5_5() {
  shown <<'EOF'
k get ingressclass
k -n ing-hosts describe ingress sites | grep -A6 Rules
k -n ing-hosts patch ingress sites --type=json -p '[{"op":"replace","path":"/spec/ingressClassName","value":"nginx"},{"op":"replace","path":"/spec/rules/1/http/paths/0/backend/service/port","value":{"name":"web"}}]'
k -n ing-hosts describe ingress sites | grep -A6 Rules
sleep 10
curl -s -H 'Host: docs.ckad.local' http://$(k get node cks-w1 -o jsonpath='{.status.addresses[0].address}'):30080/
EOF
}

# ---- Task 6: deny by default, then allow one path -----------------------------------------------------------
setup_5_6() {
  ns_fresh np-app
  web_app np-app backend backend 8080 0 app=backend
  client_pod np-app frontend role=frontend
  client_pod np-app other role=other
  all_ready np-app
  cp_sh "kubectl -n np-app get pods -o wide --show-labels"
}
B6="http://\$(kubectl -n np-app get pod backend -o jsonpath='{.status.podIP}'):8080"
check_5_6() {
  check_json "NetworkPolicy default-deny-ingress selects every pod and allows no ingress" "kubectl -n np-app get netpol default-deny-ingress -o json" \
    's=p["spec"]; s["podSelector"] in ({},{"matchLabels":{}}) and s["policyTypes"]==["Ingress"] and not s.get("ingress")'
  check_cp "frontend reaches backend on 8080" "$(reach np-app frontend "$B6") | grep -qx backend"
  check_cp "other does not reach backend" "! $(reach np-app other "$B6")"
  check_cp "backend does not reach frontend (the default deny holds)" \
    "! kubectl -n np-app exec backend -- wget -qO- -T 3 http://\$(kubectl -n np-app get pod frontend -o jsonpath='{.status.podIP}'):8080 2>&1 | grep -q 'refused'"
}
solve_5_6() {
  put_file /opt/ckad/5.6/netpol.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: np-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: np-app
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF
  shown <<'EOF'
k apply -f /opt/ckad/5.6/netpol.yaml
BACKEND=$(k -n np-app get pod backend -o jsonpath='{.status.podIP}')
k -n np-app exec frontend -- wget -qO- -T 3 http://$BACKEND:8080
k -n np-app exec other -- wget -qO- -T 3 http://$BACKEND:8080
EOF
}

# ---- Task 7: egress only to the database and DNS ------------------------------------------------------------------
setup_5_7() {
  ns_fresh np-egress np-egress-other
  web_app np-egress db db 5432 0 app=db
  web_app np-egress-other partner partner 8080 0 app=partner
  client_pod np-egress app app=app
  cp_sh 'kubectl -n np-egress expose pod db --port=5432 >/dev/null; kubectl -n np-egress-other expose pod partner --port=80 --target-port=8080 >/dev/null'
  all_ready np-egress; all_ready np-egress-other
}
check_5_7() {
  check_json "NetworkPolicy app-egress selects app=app and controls only egress" "kubectl -n np-egress get netpol app-egress -o json" \
    'p["spec"]["podSelector"]=={"matchLabels":{"app":"app"}} and p["spec"]["policyTypes"]==["Egress"]'
  check_cp "app reaches the database by name: http://db:5432" "$(reach np-egress app http://db:5432) | grep -qx db"
  check_cp "app does not reach partner.np-egress-other" "! $(reach np-egress app http://partner.np-egress-other)"
  check_cp "app does not reach the API server" "! $(reach np-egress app https://kubernetes.default)"
}
solve_5_7() {
  put_file /opt/ckad/5.7/netpol.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-egress
  namespace: np-egress
spec:
  podSelector:
    matchLabels:
      app: app
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 5432
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
  shown <<'EOF'
k apply -f /opt/ckad/5.7/netpol.yaml
k -n np-egress exec app -- wget -qO- -T 3 http://db:5432
k -n np-egress exec app -- wget -qO- -T 3 http://partner.np-egress-other
EOF
}

# ---- Task 8: traffic from one namespace, one kind of pod ----------------------------------------------------------
setup_5_8() {
  ns_fresh np-metrics np-monitoring np-dev
  cp_sh 'kubectl label ns np-monitoring team=monitoring --overwrite >/dev/null; kubectl label ns np-dev team=dev --overwrite >/dev/null'
  web_app np-metrics exporter exporter 9100 0 app=exporter
  client_pod np-monitoring prometheus app=prometheus
  client_pod np-monitoring grafana app=grafana
  client_pod np-dev prometheus app=prometheus
  all_ready np-metrics; all_ready np-monitoring; all_ready np-dev
  cp_sh 'kubectl get ns -l team --show-labels'
}
E8="http://\$(kubectl -n np-metrics get pod exporter -o jsonpath='{.status.podIP}'):9100"
check_5_8() {
  check_cp "NetworkPolicy allow-prometheus exists in np-metrics" "kubectl -n np-metrics get netpol allow-prometheus"
  check_cp "prometheus in np-monitoring reaches the exporter" "$(reach np-monitoring prometheus "$E8") | grep -qx exporter"
  check_cp "grafana in np-monitoring does not" "! $(reach np-monitoring grafana "$E8")"
  check_cp "prometheus in np-dev does not" "! $(reach np-dev prometheus "$E8")"
}
solve_5_8() {
  put_file /opt/ckad/5.8/netpol.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus
  namespace: np-metrics
spec:
  podSelector:
    matchLabels:
      app: exporter
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9100
EOF
  shown <<'EOF'
k apply -f /opt/ckad/5.8/netpol.yaml
EXPORTER=$(k -n np-metrics get pod exporter -o jsonpath='{.status.podIP}')
k -n np-monitoring exec prometheus -- wget -qO- -T 3 http://$EXPORTER:9100
k -n np-monitoring exec grafana -- wget -qO- -T 3 http://$EXPORTER:9100
k -n np-dev exec prometheus -- wget -qO- -T 3 http://$EXPORTER:9100
EOF
}

# ---- Task 9: fit a pod to policies you may not change ---------------------------------------------------------------
setup_5_9() {
  ns_fresh np-labels
  web_app np-labels payments payments 8080 0 app=payments
  client_pod np-labels checkout app=checkout
  client_pod np-labels stranger app=stranger
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: np-labels}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  egress:
  - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: payments-clients, namespace: np-labels}
spec:
  podSelector: {matchLabels: {role: payments-client}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: payments}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: payments-ingress, namespace: np-labels}
spec:
  podSelector: {matchLabels: {app: payments}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {role: payments-client, env: prod}}}]
    ports: [{protocol: TCP, port: 8080}]
EOF
  cp_sh 'kubectl -n np-labels expose pod payments --port=80 --target-port=8080 >/dev/null'
  all_ready np-labels
  cp_sh 'kubectl -n np-labels get netpol; kubectl -n np-labels get netpol -o jsonpath="{range .items[*]}{.metadata.resourceVersion} {end}" > /tmp/ckad-5.9-rv'
}
check_5_9() {
  check_cp "checkout reaches http://payments" "$(reach np-labels checkout http://payments) | grep -qx payments"
  check_cp "stranger still does not" "! $(reach np-labels stranger http://payments)"
  check_cp "the three NetworkPolicies are unchanged" \
    "[ \"\$(kubectl -n np-labels get netpol -o jsonpath='{range .items[*]}{.metadata.resourceVersion} {end}')\" = \"\$(cat /tmp/ckad-5.9-rv)\" ]"
  check_cp "checkout keeps its label app=checkout" "kubectl -n np-labels get pod checkout -o jsonpath='{.metadata.labels.app}' | grep -qx checkout"
}
solve_5_9() {
  shown <<'EOF'
k -n np-labels exec checkout -- wget -qO- -T 3 http://payments
k -n np-labels describe netpol payments-clients payments-ingress | grep -A2 -E 'PodSelector|From|To'
k -n np-labels label pod checkout role=payments-client env=prod
k -n np-labels exec checkout -- wget -qO- -T 3 http://payments
EOF
}

# ---- Task 10: a StatefulSet behind a headless Service ----------------------------------------------------------------
setup_5_10() {
  ns_fresh stateful
  client_pod stateful client
  all_ready stateful
}
check_5_10() {
  check_cp "Service db is headless" "kubectl -n stateful get svc db -o jsonpath='{.spec.clusterIP}' | grep -qx None"
  check_cp "StatefulSet db has 2 ready pods and names db as its Service" \
    "kubectl -n stateful rollout status sts db --timeout=120s && kubectl -n stateful get sts db -o jsonpath='{.spec.serviceName} {.status.readyReplicas}' | grep -qx 'db 2'"
  check_cp "db-0.db and db-1.db each answer with their own name" \
    "$(reach stateful client http://db-0.db:8080) | grep -qx db-0 && $(reach stateful client http://db-1.db.stateful.svc.cluster.local:8080) | grep -qx db-1"
}
solve_5_10() {
  put_file /opt/ckad/5.10/db.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: stateful
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 8080
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
  namespace: stateful
spec:
  serviceName: db
  replicas: 2
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && hostname > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
EOF
  shown <<'EOF'
k apply -f /opt/ckad/5.10/db.yaml
k -n stateful rollout status sts db
k -n stateful get pods -o wide
k -n stateful exec client -- nslookup db.stateful.svc.cluster.local
k -n stateful exec client -- wget -qO- http://db-1.db:8080
EOF
}
