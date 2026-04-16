# Complete Observability Stack Setup Guide
# Self-Managed Kubernetes on AWS

## Stack Overview

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              GRAFANA (Dashboard)                                 │
│                          http://grafana.yourdomain.com                           │
│                                                                                  │
│    ┌──────────────┐      ┌───────────────────┐      ┌──────────────────┐        │
│    │   Loki       │      │  VictoriaMetrics   │      │     Tempo        │        │
│    │  (Logs)      │      │  (Metrics+Alerts)  │      │    (Traces)      │        │
│    └──────┬───────┘      └─────────┬─────────┘      └────────┬─────────┘        │
└───────────┼────────────────────────┼──────────────────────────┼──────────────────┘
            │                        │                          │
            │         ┌──────────────┴──────────────┐           │
            │         │   OpenTelemetry Collector    │           │
            │         │      (DaemonSet + Gateway)   │           │
            │         └──────────────┬──────────────┘           │
            │                        │                          │
            │              ┌─────────┼─────────┐                │
            │              │         │         │                │
         ┌──┴──┐      ┌───┴──┐  ┌───┴──┐  ┌───┴──┐            │
         │Logs │      │ App1 │  │ App2 │  │ App3 │            │
         │(k8s)│      │(auth)│  │(blog)│  │(...)  │            │
         └─────┘      └──────┘  └──────┘  └──────┘
```

### Component Roles

| Component | Role | Storage | Port |
|-----------|------|---------|------|
| **OTel Collector (DaemonSet)** | Collects logs, metrics, traces from every node | — | 4317 (gRPC), 4318 (HTTP) |
| **OTel Collector (Gateway)** | Central aggregation point, routes telemetry to backends | — | 4317, 4318 |
| **Loki** | Log aggregation and querying | EBS / local-storage | 3100 |
| **VictoriaMetrics** | Metrics storage + PromQL querying + alerting | EBS / local-storage | 8428 |
| **vmalert** | Alert evaluation engine (reads VM, sends to Alertmanager) | — | 8880 |
| **vmagent** | Scrapes Prometheus metrics, writes to VM | — | 8429 |
| **Tempo** | Distributed trace storage and querying | EBS / local-storage | 3200 (HTTP), 4317 (gRPC) |
| **Grafana** | Unified dashboards for logs, metrics, traces | — | 3000 |

---

## Prerequisites

```bash
# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Helm 3.12+
helm version

# Add all required Helm repos
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add vm https://victoriametrics.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

---

## STEP 1: Create the Observability Namespace

```bash
kubectl create namespace observability
```

---

## STEP 2: Storage Setup (EBS StorageClass)

If your cluster doesn't already have a default StorageClass with EBS provisioning, create one:

```yaml
# file: k8s/observability/00-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: obs-ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  iops: "3000"
  throughput: "125"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl apply -f k8s/observability/00-storage-class.yaml
```

> **Note**: If using `local-storage` (your existing PVs), skip this and use `storageClassName: local-storage` in the Helm values below.

---

## STEP 3: VictoriaMetrics (Metrics + Alerting)

### 3.1 Why VictoriaMetrics over Prometheus?

- 10x less memory consumption
- Faster queries on large datasets
- Native clustering support
- Drop-in PromQL compatibility
- Built-in downsampling and retention

### 3.2 Install VictoriaMetrics Single-Server

For a self-managed cluster, single-server mode handles millions of active time series. Use cluster mode only if you need horizontal scaling.

```yaml
# file: k8s/observability/01-victoriametrics-values.yaml

server:
  # Data retention
  retentionPeriod: "90d"

  # Storage
  persistentVolume:
    enabled: true
    storageClass: "obs-ebs-gp3"
    size: 50Gi

  # Resources (tune based on your metrics cardinality)
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1"
      memory: "2Gi"

  # Scrape config — VictoriaMetrics will scrape itself + kube-state-metrics
  scrape:
    enabled: true
    configMap: ""
    # Additional scrape configs are added via vmagent below

  # Enable the /api/v1/write endpoint (for OTel remote_write)
  extraArgs:
    httpListenAddr: ":8428"
    # Accept OpenTelemetry metrics protocol directly
    openTelemetryListenAddr: ":4318"

  service:
    type: ClusterIP
    servicePort: 8428

  # Ingress (optional — for direct access)
  ingress:
    enabled: false
```

```bash
helm install victoriametrics vm/victoria-metrics-single \
  --namespace observability \
  --values k8s/observability/01-victoriametrics-values.yaml
```

### 3.3 Install vmagent (Scrapes metrics from all Pods/Services)

vmagent replaces Prometheus's scraping role. It discovers Kubernetes targets and remote-writes to VictoriaMetrics.

```yaml
# file: k8s/observability/02-vmagent-values.yaml

remoteWriteUrls:
  - http://victoriametrics-victoria-metrics-single-server.observability.svc:8428/api/v1/write

# Kubernetes service discovery — scrape all annotated pods
config:
  global:
    scrape_interval: 30s
    scrape_timeout: 10s

  scrape_configs:
    # 1. Scrape pods with prometheus.io annotations
    - job_name: "kubernetes-pods"
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: pod
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: replace
          target_label: app

    # 2. Scrape kube-state-metrics
    - job_name: "kube-state-metrics"
      kubernetes_sd_configs:
        - role: service
      relabel_configs:
        - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_name]
          action: keep
          regex: kube-state-metrics

    # 3. Scrape node-exporter
    - job_name: "node-exporter"
      kubernetes_sd_configs:
        - role: node
      relabel_configs:
        - action: replace
          source_labels: [__address__]
          regex: "(.*):.*"
          replacement: "$1:9100"
          target_label: __address__

    # 4. Scrape kubelet cAdvisor metrics
    - job_name: "kubelet-cadvisor"
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
        - role: node
      metrics_path: /metrics/cadvisor

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# RBAC for Kubernetes service discovery
rbac:
  create: true
  pspEnabled: false
```

```bash
helm install vmagent vm/victoria-metrics-agent \
  --namespace observability \
  --values k8s/observability/02-vmagent-values.yaml
```

### 3.4 Install vmalert (Alerting Rules Engine)

vmalert evaluates PromQL-based alerting rules against VictoriaMetrics and sends alerts to Alertmanager.

```yaml
# file: k8s/observability/03-vmalert-values.yaml

server:
  datasource:
    url: http://victoriametrics-victoria-metrics-single-server.observability.svc:8428
  notifier:
    alertmanager:
      url: http://alertmanager.observability.svc:9093
  # Remote write for recording rules
  remoteWrite:
    url: http://victoriametrics-victoria-metrics-single-server.observability.svc:8428
  remoteRead:
    url: http://victoriametrics-victoria-metrics-single-server.observability.svc:8428

  resources:
    requests:
      cpu: "50m"
      memory: "128Mi"
    limits:
      cpu: "200m"
      memory: "256Mi"

  # Define alerting rules inline or via configMap
  config:
    alerts:
      groups:
        # ── Infrastructure Alerts ──
        - name: node-alerts
          interval: 30s
          rules:
            - alert: NodeHighCPU
              expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "Node {{ $labels.instance }} CPU > 85%"

            - alert: NodeHighMemory
              expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "Node {{ $labels.instance }} memory > 85%"

            - alert: NodeDiskSpaceLow
              expr: (1 - node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"}) * 100 > 85
              for: 10m
              labels:
                severity: critical
              annotations:
                summary: "Node {{ $labels.instance }} disk usage > 85%"

        # ── Kubernetes Alerts ──
        - name: kubernetes-alerts
          interval: 30s
          rules:
            - alert: PodCrashLooping
              expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"

            - alert: PodNotReady
              expr: kube_pod_status_ready{condition="true"} == 0
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is not ready"

            - alert: DeploymentReplicasMismatch
              expr: kube_deployment_spec_replicas != kube_deployment_status_ready_replicas
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} replicas mismatch"

        # ── Application Alerts (auth-service + docker-test) ──
        - name: application-alerts
          interval: 30s
          rules:
            - alert: HighErrorRate
              expr: sum(rate(http_server_requests_total{http_status_code=~"5.."}[5m])) by (namespace, app) / sum(rate(http_server_requests_total[5m])) by (namespace, app) > 0.05
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "{{ $labels.app }} in {{ $labels.namespace }} error rate > 5%"

            - alert: HighLatencyP99
              expr: histogram_quantile(0.99, sum(rate(http_server_request_duration_seconds_bucket[5m])) by (le, namespace, app)) > 2
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "{{ $labels.app }} P99 latency > 2s"

            - alert: AppDown
              expr: up{app=~"auth-service|docker-test"} == 0
              for: 2m
              labels:
                severity: critical
              annotations:
                summary: "{{ $labels.app }} is unreachable"
```

```bash
helm install vmalert vm/victoria-metrics-alert \
  --namespace observability \
  --values k8s/observability/03-vmalert-values.yaml
```

### 3.5 Install Alertmanager (to receive alerts from vmalert)

```yaml
# file: k8s/observability/04-alertmanager.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
        - name: alertmanager
          image: prom/alertmanager:v0.27.0
          args:
            - "--config.file=/etc/alertmanager/alertmanager.yml"
            - "--storage.path=/alertmanager"
          ports:
            - containerPort: 9093
          volumeMounts:
            - name: config
              mountPath: /etc/alertmanager
            - name: storage
              mountPath: /alertmanager
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"
      volumes:
        - name: config
          configMap:
            name: alertmanager-config
        - name: storage
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: observability
spec:
  selector:
    app: alertmanager
  ports:
    - port: 9093
      targetPort: 9093
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: observability
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m

    route:
      receiver: 'default'
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

      routes:
        - receiver: 'critical-slack'
          match:
            severity: critical
          continue: true

    receivers:
      - name: 'default'
        # Configure your notification channel (Slack, PagerDuty, email, etc.)
        # Example for Slack:
        # slack_configs:
        #   - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        #     channel: '#alerts'
        #     title: '{{ .GroupLabels.alertname }}'
        #     text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

      - name: 'critical-slack'
        # slack_configs:
        #   - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        #     channel: '#critical-alerts'
```

```bash
kubectl apply -f k8s/observability/04-alertmanager.yaml
```

### 3.6 Verify VictoriaMetrics Stack

```bash
# Check all pods are running
kubectl get pods -n observability -l "app.kubernetes.io/name=victoria-metrics-single"
kubectl get pods -n observability -l "app.kubernetes.io/name=victoria-metrics-agent"
kubectl get pods -n observability -l "app.kubernetes.io/name=victoria-metrics-alert"
kubectl get pods -n observability -l "app=alertmanager"

# Port-forward to verify VM is receiving data
kubectl port-forward -n observability svc/victoriametrics-victoria-metrics-single-server 8428:8428 &
curl -s "http://localhost:8428/api/v1/query?query=up" | python3 -m json.tool

# Check vmagent targets
kubectl port-forward -n observability svc/vmagent-victoria-metrics-agent 8429:8429 &
curl -s "http://localhost:8429/targets"
```

---

## STEP 4: Loki (Log Aggregation)

### 4.1 Install Loki (SimpleScalable mode)

For a self-managed cluster, SimpleScalable mode gives you read/write separation without the complexity of full microservices mode.

```yaml
# file: k8s/observability/05-loki-values.yaml

# -- Deployment mode: simple-scalable
deploymentMode: SimpleScalable

loki:
  auth_enabled: false

  # Storage — use filesystem for self-managed (use S3 for production scale)
  storage:
    type: filesystem

  commonConfig:
    replication_factor: 1

  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h

  limits_config:
    retention_period: 30d             # Keep logs for 30 days
    max_query_length: 721h
    max_query_parallelism: 32
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20
    per_stream_rate_limit: 5MB
    per_stream_rate_limit_burst: 15MB

  compactor:
    retention_enabled: true
    delete_request_store: filesystem

  # Accept OTLP log format directly
  otlp:
    resource_attributes:
      attributes_config:
        - action: index_label
          attributes:
            - k8s.namespace.name
            - k8s.pod.name
            - k8s.container.name
            - service.name
            - service.namespace

# Storage for write/read replicas
write:
  replicas: 2
  persistence:
    size: 20Gi
    storageClass: "obs-ebs-gp3"
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

read:
  replicas: 2
  persistence:
    size: 10Gi
    storageClass: "obs-ebs-gp3"
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

backend:
  replicas: 1
  persistence:
    size: 20Gi
    storageClass: "obs-ebs-gp3"
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

# Disable built-in gateway — OTel Collector sends directly
gateway:
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"

# Disable Grafana/Prometheus bundled components (we install separately)
monitoring:
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false
  lokiCanary:
    enabled: false

test:
  enabled: false
```

```bash
helm install loki grafana/loki \
  --namespace observability \
  --values k8s/observability/05-loki-values.yaml
```

### 4.2 Verify Loki

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=loki

# Port-forward to check readiness
kubectl port-forward -n observability svc/loki-gateway 3100:80 &
curl -s http://localhost:3100/ready
# Expected: "ready"
```

---

## STEP 5: Tempo (Distributed Tracing)

### 5.1 Install Tempo

```yaml
# file: k8s/observability/06-tempo-values.yaml

tempo:
  # Receive traces via OTLP (from OTel Collector)
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"

  # Enable metrics generation from traces (RED metrics)
  metricsGenerator:
    enabled: true
    remoteWriteUrl: "http://victoriametrics-victoria-metrics-single-server.observability.svc:8428/api/v1/write"

  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
      wal:
        path: /var/tempo/wal

  # Retention
  compactor:
    compaction:
      block_retention: 72h          # Keep traces for 3 days

  # Global overrides
  overrides:
    defaults:
      ingestion:
        rate_limit_bytes: 15000000   # 15MB/s
        burst_size_bytes: 20000000

persistence:
  enabled: true
  storageClass: "obs-ebs-gp3"
  size: 20Gi

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"

# Enable service graph metrics (generates relationship data for Grafana)
metricsGenerator:
  enabled: true
  config:
    storage:
      remote_write:
        - url: "http://victoriametrics-victoria-metrics-single-server.observability.svc:8428/api/v1/write"
    registry:
      collection_interval: 15s
      stale_duration: 15m
    processor:
      service_graphs:
        dimensions:
          - service.namespace
          - http.method
          - http.status_code
      span_metrics:
        dimensions:
          - service.namespace
          - http.method
          - http.status_code
          - http.route
```

```bash
helm install tempo grafana/tempo \
  --namespace observability \
  --values k8s/observability/06-tempo-values.yaml
```

### 5.2 Verify Tempo

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=tempo

# Port-forward and check readiness
kubectl port-forward -n observability svc/tempo 3200:3200 &
curl -s http://localhost:3200/ready
```

---

## STEP 6: OpenTelemetry Collector

This is the central nervous system. We deploy two tiers:

1. **DaemonSet Collector** — runs on every node, collects logs from containers, receives app traces/metrics via OTLP
2. **Gateway Collector** — central aggregation point, fans out to Loki/VM/Tempo

### 6.1 Install OTel Collector DaemonSet (Node-level)

```yaml
# file: k8s/observability/07-otel-daemonset-values.yaml

mode: daemonset

presets:
  # Automatically collect logs from all containers via filelog receiver
  logsCollection:
    enabled: true
    includeCollectorLogs: false
    storeCheckpoints: true

  # Collect Kubernetes metadata (pod name, namespace, labels, etc.)
  kubernetesAttributes:
    enabled: true
    extractAllPodLabels: true
    extractAllPodAnnotations: false

  # Collect kubelet metrics
  kubeletMetrics:
    enabled: true

config:
  receivers:
    # OTLP — apps send traces/metrics here
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"

    # filelog is auto-configured by logsCollection preset
    # It reads /var/log/pods/*/*.log

  processors:
    # Add k8s metadata to telemetry
    k8sattributes:
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.node.name
          - k8s.container.name
          - k8s.deployment.name
          - k8s.replicaset.name
        labels:
          - tag_name: app
            key: app
            from: pod
          - tag_name: component
            key: component
            from: pod

    # Memory limiter prevents OOM
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25

    # Batch telemetry before sending (reduces network calls)
    batch:
      send_batch_size: 1024
      send_batch_max_size: 2048
      timeout: 5s

    # Add resource attributes
    resource:
      attributes:
        - key: k8s.cluster.name
          value: "self-managed-aws"
          action: upsert

  exporters:
    # Logs → Loki via OTLP
    otlphttp/loki:
      endpoint: http://loki-gateway.observability.svc:80/otlp
      tls:
        insecure: true

    # Metrics → VictoriaMetrics via Prometheus remote write
    prometheusremotewrite/vm:
      endpoint: http://victoriametrics-victoria-metrics-single-server.observability.svc:8428/api/v1/write
      resource_to_telemetry_conversion:
        enabled: true

    # Traces → Tempo via OTLP gRPC
    otlp/tempo:
      endpoint: tempo.observability.svc:4317
      tls:
        insecure: true

    # Debug exporter (enable temporarily for troubleshooting)
    # debug:
    #   verbosity: detailed

  service:
    pipelines:
      logs:
        receivers: [filelog]
        processors: [k8sattributes, resource, memory_limiter, batch]
        exporters: [otlphttp/loki]

      metrics:
        receivers: [otlp]
        processors: [k8sattributes, resource, memory_limiter, batch]
        exporters: [prometheusremotewrite/vm]

      traces:
        receivers: [otlp]
        processors: [k8sattributes, resource, memory_limiter, batch]
        exporters: [otlp/tempo]

# Resources for DaemonSet pods
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Service account with RBAC for k8s metadata
serviceAccount:
  create: true

clusterRole:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods", "namespaces", "nodes", "nodes/proxy", "services", "endpoints"]
      verbs: ["get", "list", "watch"]
    - apiGroups: ["apps"]
      resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
      verbs: ["get", "list", "watch"]

# Tolerations to run on all nodes including control-plane
tolerations:
  - operator: Exists

# Host paths needed for log collection
extraVolumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers

extraVolumeMounts:
  - name: varlogpods
    mountPath: /var/log/pods
    readOnly: true
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true

# Ports to expose on each node
ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    hostPort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    hostPort: 4318
    protocol: TCP
```

```bash
helm install otel-daemonset open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values k8s/observability/07-otel-daemonset-values.yaml
```

### 6.2 Verify OTel Collector

```bash
# Check DaemonSet pods run on all nodes
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector -o wide

# Check logs for errors
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=50
```

---

## STEP 7: Grafana (Unified Dashboard)

### 7.1 Install Grafana

```yaml
# file: k8s/observability/08-grafana-values.yaml

replicas: 1

persistence:
  enabled: true
  storageClassName: "obs-ebs-gp3"
  size: 5Gi

# Admin credentials (change these or use a Secret)
adminUser: admin
adminPassword: ""   # Leave empty — Grafana generates one, retrieve via kubectl

# Pre-configure all data sources
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      # VictoriaMetrics as Prometheus-compatible source
      - name: VictoriaMetrics
        type: prometheus
        uid: victoriametrics
        url: http://victoriametrics-victoria-metrics-single-server.observability.svc:8428
        access: proxy
        isDefault: true
        jsonData:
          timeInterval: "30s"
          httpMethod: POST

      # Loki for logs
      - name: Loki
        type: loki
        uid: loki
        url: http://loki-gateway.observability.svc:80
        access: proxy
        jsonData:
          derivedFields:
            # Link trace IDs in logs → Tempo traces
            - name: TraceID
              datasourceUid: tempo
              matcherRegex: '"trace_id":"(\w+)"'
              url: "$${__value.raw}"
              urlDisplayLabel: "View Trace"

      # Tempo for traces
      - name: Tempo
        type: tempo
        uid: tempo
        url: http://tempo.observability.svc:3200
        access: proxy
        jsonData:
          tracesToLogsV2:
            datasourceUid: loki
            spanStartTimeShift: "-1h"
            spanEndTimeShift: "1h"
            filterByTraceID: true
            filterBySpanID: false
            customQuery: true
            query: '{k8s_namespace_name="${__span.tags["service.namespace"]}"} | json | trace_id = `${__span.traceId}`'
          tracesToMetrics:
            datasourceUid: victoriametrics
            spanStartTimeShift: "-1h"
            spanEndTimeShift: "1h"
            tags:
              - key: service.name
                value: service
            queries:
              - name: "Request Rate"
                query: 'sum(rate(traces_spanmetrics_calls_total{service="$${__tags.service}"}[5m]))'
              - name: "Error Rate"
                query: 'sum(rate(traces_spanmetrics_calls_total{service="$${__tags.service}", status_code="STATUS_CODE_ERROR"}[5m]))'
          serviceMap:
            datasourceUid: victoriametrics
          nodeGraph:
            enabled: true
          lokiSearch:
            datasourceUid: loki

      # Alertmanager source
      - name: Alertmanager
        type: alertmanager
        url: http://alertmanager.observability.svc:9093
        access: proxy
        jsonData:
          implementation: prometheus

# Pre-provision dashboards
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: "default"
        orgId: 1
        folder: ""
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

# Community dashboards to auto-import
dashboards:
  default:
    # Kubernetes cluster overview
    k8s-cluster:
      gnetId: 7249
      revision: 1
      datasource: VictoriaMetrics
    # Node Exporter
    node-exporter:
      gnetId: 1860
      revision: 37
      datasource: VictoriaMetrics
    # Kubernetes pods
    k8s-pods:
      gnetId: 6417
      revision: 1
      datasource: VictoriaMetrics

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Ingress for external access
ingress:
  enabled: true
  ingressClassName: alb   # Change to "nginx" if using Nginx Ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:177701659471:certificate/YOUR_CERT_ID"
  hosts:
    - grafana.yourdomain.com
  path: /
  pathType: Prefix
```

```bash
helm install grafana grafana/grafana \
  --namespace observability \
  --values k8s/observability/08-grafana-values.yaml
```

### 7.2 Get Grafana Admin Password

```bash
kubectl get secret grafana -n observability -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

### 7.3 Access Grafana

```bash
# If no ingress configured, port-forward:
kubectl port-forward -n observability svc/grafana 3000:80

# Open http://localhost:3000
# Login: admin / <password from above>
```

### 7.4 Verify All Data Sources

In Grafana UI: **Connections → Data sources → Test each one**

| Data Source | Expected | Test Query |
|---|---|---|
| VictoriaMetrics | ✅ Connected | `up` |
| Loki | ✅ Connected | `{namespace="auth-service"}` |
| Tempo | ✅ Connected | Search recent traces |
| Alertmanager | ✅ Connected | View active alerts |

---

## STEP 8: Application-Side Tracing

### Tracing Approach Decision

| Approach | How | Pros | Cons |
|---|---|---|---|
| **Auto-instrumentation (Recommended)** | OTel K8s Operator injects instrumentation at pod startup | Zero code changes, covers HTTP/DB/Redis automatically | Slightly less control over custom spans |
| **Manual SDK instrumentation** | Add `opentelemetry-sdk` gems to your Rails apps | Full control, custom spans/attributes | Requires code changes, maintenance burden |

**Recommendation: Use auto-instrumentation.** For your Rails apps, the OTel Operator can inject Ruby auto-instrumentation without touching application code. This covers HTTP requests, database queries, and Redis calls automatically.

### 8.1 Install OpenTelemetry Operator

```bash
# Install cert-manager (required by OTel Operator for webhook certificates)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s

# Install OTel Operator
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# Verify
kubectl get pods -n opentelemetry-operator-system
```

### 8.2 Create Auto-Instrumentation Resource for Ruby

```yaml
# file: k8s/observability/09-auto-instrumentation.yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: ruby-instrumentation
  namespace: auth-service          # Deploy in each app namespace
spec:
  exporter:
    # Send to OTel Collector DaemonSet on the same node
    endpoint: http://otel-daemonset-opentelemetry-collector.observability.svc:4318
  propagators:
    - tracecontext                 # W3C Trace Context (standard)
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "1.0"                # Sample 100% of traces (reduce in high-traffic production)
  ruby:
    env:
      - name: OTEL_RUBY_DISABLED_INSTRUMENTATIONS
        value: ""                  # Empty = enable all available instrumentations
      - name: OTEL_SERVICE_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['app']
      - name: OTEL_RESOURCE_ATTRIBUTES
        value: "service.namespace=$(OTEL_RESOURCE_ATTRIBUTES_NAMESPACE)"
      - name: OTEL_RESOURCE_ATTRIBUTES_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
---
# Same for docker-test namespace
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: ruby-instrumentation
  namespace: default               # Adjust to your docker-test namespace
spec:
  exporter:
    endpoint: http://otel-daemonset-opentelemetry-collector.observability.svc:4318
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "1.0"
  ruby:
    env:
      - name: OTEL_RUBY_DISABLED_INSTRUMENTATIONS
        value: ""
      - name: OTEL_SERVICE_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['app']
```

```bash
kubectl apply -f k8s/observability/09-auto-instrumentation.yaml
```

### 8.3 Annotate Your Application Deployments

Add **one annotation** to your existing deployment pods. This tells the OTel Operator to inject Ruby auto-instrumentation into the pod at startup.

**For rails-auth-service** — edit [k8s/06-application.yaml](k8s/06-application.yaml):

```yaml
spec:
  template:
    metadata:
      annotations:
        # Existing annotations
        prometheus.io/scrape: "true"
        prometheus.io/port: "3000"
        prometheus.io/path: "/metrics"
        # ADD THIS LINE — enables auto-instrumentation
        instrumentation.opentelemetry.io/inject-ruby: "true"
```

**For docker-test** — add the same annotation to its deployment:

```yaml
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-ruby: "true"
```

### 8.4 What Auto-Instrumentation Covers (Zero Code Changes)

The OTel Ruby auto-instrumentation automatically traces:

| Library | What gets traced |
|---|---|
| **Rack/Rails** | Every HTTP request (method, path, status, duration) |
| **ActionController** | Controller action names, render times |
| **ActiveRecord** | SQL queries (db.system, db.statement, db.name) |
| **MySQL2** | Database connections and query execution |
| **Net::HTTP / HTTParty** | Outbound HTTP calls (your AuthServiceClient calls!) |
| **Redis** | Redis commands (if you add Redis later) |
| **Puma** | Thread/worker metrics |

**This means**: When docker-test calls `AuthServiceClient.sign_in()`, the trace will automatically propagate from docker-test → rails-auth-service, showing the full distributed trace across both services.

### 8.5 Restart Deployments to Activate

```bash
# Restart auth-service to inject instrumentation
kubectl rollout restart deployment/auth-service-app -n auth-service

# Restart docker-test
kubectl rollout restart deployment/docker-test-app -n default  # adjust namespace
```

### 8.6 Verify Traces

```bash
# Check that the init container was injected
kubectl get pod -n auth-service -l app=auth-service -o jsonpath='{.items[0].spec.initContainers[*].name}'
# Expected output should include: opentelemetry-auto-instrumentation-ruby

# Generate some traffic
curl -X POST https://auth.yourdomain.com/users/sign_in \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"test@example.com","password":"TestPass123"}}'

# Check Tempo for traces (via Grafana or API)
kubectl port-forward -n observability svc/tempo 3200:3200 &
curl -s "http://localhost:3200/api/search?tags=service.name%3Dauth-service&limit=5" | python3 -m json.tool
```

---

## STEP 9: Complete Deployment Order

Execute in this exact order:

```bash
# 0. Namespace
kubectl create namespace observability

# 1. Storage class
kubectl apply -f k8s/observability/00-storage-class.yaml

# 2. VictoriaMetrics (metrics storage)
helm install victoriametrics vm/victoria-metrics-single \
  --namespace observability \
  --values k8s/observability/01-victoriametrics-values.yaml

# 3. vmagent (scrapes metrics)
helm install vmagent vm/victoria-metrics-agent \
  --namespace observability \
  --values k8s/observability/02-vmagent-values.yaml

# 4. Alertmanager (receives alerts)
kubectl apply -f k8s/observability/04-alertmanager.yaml

# 5. vmalert (evaluates rules, sends to alertmanager)
helm install vmalert vm/victoria-metrics-alert \
  --namespace observability \
  --values k8s/observability/03-vmalert-values.yaml

# 6. Loki (log storage)
helm install loki grafana/loki \
  --namespace observability \
  --values k8s/observability/05-loki-values.yaml

# 7. Tempo (trace storage)
helm install tempo grafana/tempo \
  --namespace observability \
  --values k8s/observability/06-tempo-values.yaml

# 8. OTel Collector DaemonSet (collects and routes everything)
helm install otel-daemonset open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values k8s/observability/07-otel-daemonset-values.yaml

# 9. Grafana (dashboards)
helm install grafana grafana/grafana \
  --namespace observability \
  --values k8s/observability/08-grafana-values.yaml

# 10. OTel Operator + Auto-instrumentation (tracing)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
kubectl apply -f k8s/observability/09-auto-instrumentation.yaml

# 11. Annotate and restart app deployments
kubectl rollout restart deployment/auth-service-app -n auth-service
```

---

## STEP 10: Final Health Check

```bash
echo "=== Checking all observability components ==="

echo "--- VictoriaMetrics ---"
kubectl get pods -n observability | grep victoria

echo "--- vmagent ---"
kubectl get pods -n observability | grep vmagent

echo "--- vmalert ---"
kubectl get pods -n observability | grep vmalert

echo "--- Alertmanager ---"
kubectl get pods -n observability | grep alertmanager

echo "--- Loki ---"
kubectl get pods -n observability | grep loki

echo "--- Tempo ---"
kubectl get pods -n observability | grep tempo

echo "--- OTel Collector ---"
kubectl get pods -n observability | grep otel

echo "--- Grafana ---"
kubectl get pods -n observability | grep grafana

echo "--- OTel Operator ---"
kubectl get pods -n opentelemetry-operator-system

echo ""
echo "=== All pods should be Running ==="
kubectl get pods -n observability --no-headers | awk '{print $3}' | sort | uniq -c
```

---

## Architecture Data Flow Summary

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Your Application Pods                             │
│                                                                       │
│  auth-service-app          docker-test-app                           │
│  ┌─────────────────┐      ┌─────────────────┐                       │
│  │ Rails App        │      │ Rails App        │                       │
│  │ (auto-instrumented)│    │ (auto-instrumented)│                    │
│  │                   │      │                   │                     │
│  │ stdout/stderr ────┼──────┼─── stdout/stderr  │                    │
│  │ OTLP traces ──────┼──────┼─── OTLP traces   │                    │
│  │ /metrics (prom) ──┼──────┼─── /metrics       │                    │
│  └─────────────────┘      └─────────────────┘                       │
└─────────┬─────────────────────────┬──────────────────────────────────┘
          │                         │
          ▼                         ▼
┌──────────────────────────────────────────────┐
│    OTel Collector DaemonSet (per node)        │
│                                               │
│  Receivers:                                   │
│    • filelog    (container logs from disk)    │
│    • otlp      (traces from apps)             │
│                                               │
│  Processors:                                  │
│    • k8sattributes (enrich with pod metadata)│
│    • resource      (add cluster name)        │
│    • batch         (efficient batching)      │
│    • memory_limiter                          │
│                                               │
│  Exporters:                                   │
│    • otlphttp/loki  → Loki (logs)            │
│    • prometheusremotewrite → VM (metrics)    │
│    • otlp/tempo     → Tempo (traces)         │
└───┬──────────────────┬──────────────┬────────┘
    │                  │              │
    ▼                  ▼              ▼
┌────────┐     ┌────────────┐   ┌─────────┐
│  Loki  │     │ Victoria   │   │  Tempo  │
│        │     │ Metrics    │   │         │
│ Logs   │     │ Metrics    │   │ Traces  │
│ 30d    │     │ 90d        │   │ 3d      │
└───┬────┘     └─────┬──────┘   └────┬────┘
    │                │               │
    │          ┌─────┴──────┐        │
    │          │  vmagent   │        │
    │          │ (scrapes   │        │
    │          │  /metrics) │        │
    │          └────────────┘        │
    │                │               │
    │          ┌─────┴──────┐        │
    │          │  vmalert   │        │
    │          │ (rules →   │        │
    │          │ alertmgr)  │        │
    │          └────────────┘        │
    │                                │
    ▼                                ▼
┌──────────────────────────────────────────┐
│              GRAFANA                      │
│                                          │
│  • Logs Explorer    (Loki queries)       │
│  • Metrics Dashboards (PromQL on VM)     │
│  • Trace Explorer   (Tempo search)       │
│  • Service Map      (auto-generated)     │
│  • Alerts           (from Alertmanager)  │
│                                          │
│  Correlation:                            │
│    Log → Trace (trace_id link)           │
│    Trace → Log  (span → Loki query)     │
│    Trace → Metrics (RED metrics)         │
└──────────────────────────────────────────┘
```

---

## Troubleshooting

### Logs not appearing in Loki

```bash
# Check OTel Collector logs for export errors
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=100 | grep -i error

# Verify filelog receiver is reading pods
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=50 | grep filelog

# Check Loki is receiving data
kubectl port-forward -n observability svc/loki-gateway 3100:80 &
curl -s "http://localhost:3100/loki/api/v1/query?query={namespace=\"auth-service\"}&limit=5"
```

### Traces not appearing in Tempo

```bash
# Check if auto-instrumentation init container was injected
kubectl describe pod -n auth-service -l app=auth-service | grep -A 5 "Init Containers"

# Check OTEL env vars are set in the app container
kubectl exec -n auth-service deploy/auth-service-app -- env | grep OTEL

# Check Tempo is receiving
kubectl port-forward -n observability svc/tempo 3200:3200 &
curl -s "http://localhost:3200/api/search?limit=5"
```

### Metrics not in VictoriaMetrics

```bash
# Check vmagent targets
kubectl port-forward -n observability svc/vmagent-victoria-metrics-agent 8429:8429 &
curl -s "http://localhost:8429/targets" | grep -c "up"

# Query VM directly
kubectl port-forward -n observability svc/victoriametrics-victoria-metrics-single-server 8428:8428 &
curl -s "http://localhost:8428/api/v1/query?query=up" | python3 -m json.tool
```

### OTel Collector OOMKilled

```bash
# Increase memory limits in values file
# resources.limits.memory: "1Gi"  →  "2Gi"
# Also increase memory_limiter.limit_percentage to match

# Apply
helm upgrade otel-daemonset open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values k8s/observability/07-otel-daemonset-values.yaml
```

---

## Resource Estimates (3-node cluster)

| Component | CPU Request | Memory Request | Storage |
|---|---|---|---|
| VictoriaMetrics | 250m | 512Mi | 50Gi EBS |
| vmagent | 100m | 256Mi | — |
| vmalert | 50m | 128Mi | — |
| Alertmanager | 50m | 64Mi | — |
| Loki (write x2) | 200m | 512Mi | 40Gi EBS |
| Loki (read x2) | 200m | 512Mi | 20Gi EBS |
| Loki (backend) | 100m | 256Mi | 20Gi EBS |
| Tempo | 100m | 256Mi | 20Gi EBS |
| OTel DaemonSet (x3 nodes) | 300m | 768Mi | — |
| Grafana | 100m | 256Mi | 5Gi EBS |
| **Total** | **~1.5 CPU** | **~3.5Gi** | **~155Gi** |
