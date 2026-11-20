# CKAD glossary

Every term the CKAD track uses, in plain words, grouped by the domain that introduces it. The CKS track's terms, such as static pod or Pod Security Standards, sit in the course's [glossary](../../platform-engineering/glossary.md#cks-exam-track).

## Images and workloads (domain 01)

### Image

A packed, read-only file system with a program and everything it needs, plus settings such as the command to start and the user to run as. A node fetches an image by name and starts containers from it, so the same image runs the same way on every node.

### Dockerfile

A text file with build instructions, one per line, such as `FROM`, `COPY`, `RUN` and `CMD`. A build tool like podman or Docker reads it and turns it into an image.

### Layer

The file system changes of one Dockerfile instruction, saved as one archive. An image is a stack of layers, and images that share a base share its layers, so a registry stores and a node downloads each layer only once.

### Registry

A server that stores images and hands them out by name, such as Docker Hub or the practice cluster's `registry.ckad:5000`. The host part of an image name says which registry holds it.

### Tag

The part of an image name after the colon, such as `v1` in `greeter:v1`, which names one version of a repository. A tag is movable, so `latest` today may point at a different image tomorrow.

### podman

A container tool with the same commands as Docker, such as `podman build`, `podman push` and `podman save`, that needs no background service. The practice cluster runs it on `cks-cp`.

### Pod template

The pod spec inside a workload object, under `spec.template`, from which its controller creates every pod. Changing the template of a Deployment starts a rollout.

### Job

A workload that runs pods until a set number of them finish with exit code 0, then stops. It retries failed pods up to its `backoffLimit`.

### CronJob

A workload that creates a Job on a schedule written in cron syntax, such as `*/30 * * * *` for every half hour.

### emptyDir

A volume that starts empty when the pod lands on a node and lives exactly as long as the pod. Containers of one pod share files through it.

### Init container

A container in the pod's `initContainers` list that runs to completion before the app containers start. The kubelet runs init containers one at a time, in order.

### Native sidecar

An init container with `restartPolicy: Always`. It starts before the app containers, keeps running for the pod's whole life, and stops after them, so it suits log shippers and proxies, also in Jobs. Stable since Kubernetes 1.33.

### PersistentVolume

A piece of storage that the cluster knows about, such as a disk, a share or a node folder, with a size and access modes. It belongs to the whole cluster, not to a namespace.

### PersistentVolumeClaim

A namespace's request for storage of a size, an access mode and a StorageClass. The control plane binds it to a matching PersistentVolume, and a pod mounts the claim, never the volume directly.

### Access mode

How nodes may mount a volume: `ReadWriteOnce` lets one node write, `ReadOnlyMany` lets many nodes read, and `ReadWriteMany` lets many nodes write.

### StorageClass

A named kind of storage, such as fast or cheap, that a claim asks for. With a provisioner, the cluster creates a matching PersistentVolume on demand; without one, the class name only has to match a volume you created.

### Toleration

A pod setting that lets the pod run on a node with a matching taint. The control plane node's taint `node-role.kubernetes.io/control-plane:NoSchedule` keeps pods away unless they tolerate it.

## Deployments and packages (domain 02)

### ReplicaSet

The object that keeps a number of identical pods running. A Deployment creates one ReplicaSet per version of its pod template and moves pods between them.

### Rolling update

A Deployment's default way to change versions: it starts new pods and stops old ones in small steps, set by `maxSurge` and `maxUnavailable`, so some pods serve requests throughout.

### Blue-green deployment

A release pattern with two complete versions running side by side, where one change to the Service's selector moves all traffic from the old version, blue, to the new one, green.

### Canary release

A release pattern that sends a small share of the traffic to the new version first. With plain Kubernetes, the share follows the pod counts behind one Service.

### Helm

A package manager for Kubernetes that installs charts, fills their templates with values, and keeps a numbered history of every installation.

### Helm chart

A package for Helm: a folder of manifest templates and a `values.yaml` file with defaults.

### Helm release

One installation of a chart in a namespace, under a name. Every install, upgrade and rollback adds a revision, which Helm stores as a Secret in that namespace.

### Chart repository

A server that hands out charts, added with `helm repo add`. An OCI registry, the same kind that stores images, also serves charts, addressed as `oci://host/path/chart`.

### Kustomize base

A folder of plain manifests with a `kustomization.yaml` that lists them, which overlays build on. Kustomize is built into `kubectl`.

### Kustomize overlay

A folder whose `kustomization.yaml` points at a base and lists changes for one environment, such as a namespace, a name prefix, labels, replica counts, image tags and patches. `kubectl apply -k` applies the result.

## Health and debugging (domain 03)

### Probe

A test the kubelet runs against a container on a schedule: an HTTP request, a TCP connection, a command, or a gRPC health call.

### Readiness probe

A probe that decides whether a pod gets requests. A failure takes the pod out of its Services' endpoints without restarting anything.

### Liveness probe

A probe that decides whether a container still works. After `failureThreshold` failures in a row, the kubelet kills the container and starts it again.

### Startup probe

A probe for slow-starting apps. Until it succeeds once, the kubelet runs no liveness or readiness probe on the container.

### EndpointSlice

The list of ready pod addresses and ports behind a Service, which the control plane keeps current. kube-proxy and ingress controllers read it to know where to send traffic.

### Event

A short record that a component writes about an object, such as a failed schedule, an image pull or a probe failure. `kubectl describe` and `kubectl events` show them, and the API server keeps them for one hour.

### metrics-server

A cluster add-on that collects CPU and memory use from every kubelet and serves it through the API, which `kubectl top` reads.

### Distroless image

An image with only the app and its libraries, without a shell or tools, which makes it small and leaves an attacker little to use.

### Ephemeral container

A temporary container that `kubectl debug` adds to a running pod, with an image you choose. With `--target`, it shares the process namespace of one container, so it sees that container's processes.

## Configuration and security (domain 04)

### ConfigMap

An object that holds settings as keys and values, either short strings or whole files, which pods read as environment variables or as files in a volume.

### Secret

An object like a ConfigMap for passwords, tokens and keys. Its values sit in base64 and are not encrypted unless the cluster turns on encryption at rest.

### base64

An encoding that writes any bytes as plain letters and digits, so binary data fits into YAML and JSON. Anyone reverses it with `base64 -d`, so it hides nothing.

### QoS class

The kubelet's ranking of a pod from its requests and limits: `Guaranteed`, `Burstable` or `BestEffort`. When a node runs out of memory, `BestEffort` pods go first and `Guaranteed` pods last.

### LimitRange

A namespace object that fills in default requests and limits for containers that name none, and refuses containers outside a minimum and maximum.

### ResourceQuota

A namespace object that caps the totals of a namespace, such as the sum of CPU requests or the number of pods, and refuses new objects past those totals.

### ServiceAccount

An identity for programs in pods. The kubelet mounts a short-lived token for the pod's ServiceAccount, which the pod sends to the API server to prove who it is.

### RBAC

Role-based access control: the API server's way to decide what an identity may do, from Roles that list allowed verbs on resources and bindings that grant them.

### Role

A list of rules, each allowing some verbs on some resources, valid inside one namespace. A ClusterRole is the same for the whole cluster.

### RoleBinding

The object that gives a Role, or a ClusterRole, to users, groups or ServiceAccounts, inside the RoleBinding's namespace. A ClusterRoleBinding does it for the whole cluster.

### Admission controller

A step in the API server, after authentication and authorization, that inspects and may change or refuse an object before it gets stored. LimitRange, ResourceQuota and Pod Security Admission all work this way.

### Pod Security Admission

The built-in admission controller that refuses pods which break a namespace's Pod Security level, `baseline` or `restricted`, set with the label `pod-security.kubernetes.io/enforce`.

### Security context

The part of a pod or container spec that sets the process's user, group, capabilities, privilege escalation and file system access.

### CustomResourceDefinition

An object that adds a new resource type to the API server, with a name, a group, versions and a schema, so `kubectl` handles it like a built-in type.

### Custom resource

An object of a type that a CustomResourceDefinition added, such as a `Backup`. On its own it only stores data.

### Operator

A controller, running in a pod, that watches custom resources of its type and makes the cluster match them, for example by running a backup for every `Backup` object.

## Networking (domain 05)

### Service

A stable virtual IP address and DNS name in front of a set of pods, picked by label. kube-proxy on every node forwards connections to one of the ready pods.

### StatefulSet

A workload whose pods get fixed names, `db-0` and `db-1`, a fixed start order, and their own storage. With a headless Service, each pod also gets its own DNS name.

### Ingress controller

A reverse proxy in the cluster, such as ingress-nginx, that reads Ingress objects and routes HTTP requests to Services by host name and path.

### Ingress

An object with HTTP routing rules, host and path to Service and port, for the ingress controller whose class it names in `ingressClassName`.

### NetworkPolicy

A firewall rule for pods: it selects pods by label and lists the peers and ports that may reach them, or that they may reach. The network plugin enforces it.
