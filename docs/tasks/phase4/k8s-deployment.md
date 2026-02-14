# P4-T1: Kubernetes / k3s Deployment

**Phase**: 4 — k3s / Kubernetes Deployment
**Size**: L
**Dependencies**: P1-T1 (reuses collector config), P3-T1 (repo documented)

## Goal

Provide Kubernetes manifests and Helm chart examples for deploying the OTel Collector into an existing k3s/k8s cluster
that already has Prometheus, Loki, and Grafana. Include an ArgoCD Application manifest for GitOps workflows and a
deployment guide covering networking (Tailscale).

## Scope

**In scope**:

- Plain Kubernetes manifests (`k8s/base/`) using Kustomize structure
- Helm values file for the official `open-telemetry/opentelemetry-collector` chart
- ArgoCD Application manifest example
- Deployment documentation (`docs/k8s-deployment.md`)
- Networking guidance for exposing the collector externally (Tailscale, NodePort)

**Non-goals**:

- No Terraform / Pulumi / CDK
- No deploying Prometheus/Loki/Grafana — those already exist in the user's cluster
- No Operator-based deployment (overkill for a single collector)
- No multi-replica / HA collector setup (single replica is sufficient for individual dev telemetry)

## Deliverables

- [ ] `k8s/base/kustomization.yaml`
- [ ] `k8s/base/namespace.yaml`
- [ ] `k8s/base/configmap.yaml` (embeds the collector config from P1-T1)
- [ ] `k8s/base/deployment.yaml`
- [ ] `k8s/base/service.yaml`
- [ ] `k8s/helm/values.yaml` (for `open-telemetry/opentelemetry-collector` chart)
- [ ] `k8s/argocd/application.yaml`
- [ ] `docs/k8s-deployment.md`

## Implementation Notes

### k8s/base/ (Kustomize manifests)

**namespace.yaml**: Create `cc-otel` namespace.

**configmap.yaml**: Embed the collector config from `otel-collector-config.yaml` (P1-T1), with the following
adjustments from the docker-compose version:

- Prometheus remote write endpoint → cluster-internal Prometheus URL (e.g.,
  `http://prometheus-server.monitoring.svc.cluster.local:9090/api/v1/write`)
- Loki push endpoint → cluster-internal Loki URL (e.g.,
  `http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push`)
- These URLs are documented as "replace with your actual service URLs" with clear comments.

**deployment.yaml**:

- Single replica
- Image: `otel/opentelemetry-collector-contrib:<pinned-version>` (same version as docker-compose)
- Mount configmap as volume
- Readiness probe on `:13133` (health check extension)
- Liveness probe on `:13133`
- Resource requests: 128Mi memory, 100m CPU
- Resource limits: 256Mi memory, 250m CPU

**service.yaml**:

- ClusterIP service exposing ports 4317 (gRPC), 4318 (HTTP), 13133 (health)
- Optionally annotated for Tailscale exposure (documented in guide)

**kustomization.yaml**: References all the above.

### k8s/helm/ (Helm values)

Values file for the official chart (`open-telemetry/opentelemetry-collector`):

- Mode: `deployment` (not daemonset — this is a centralized receiver, not a node agent)
- Config: inline collector config (same as configmap above)
- Ports: 4317, 4318, 13133
- Resources: same as base manifests

### k8s/argocd/ (GitOps)

ArgoCD Application manifest that:

- Points to this repo's `k8s/base/` directory
- Targets the `cc-otel` namespace
- Uses automated sync with self-heal

### docs/k8s-deployment.md

Sections:

1. **Prerequisites** — existing k8s cluster with Prometheus + Loki, `kubectl` access, Helm (optional)
2. **Option A: Plain manifests** — `kubectl apply -k k8s/base/` with instructions to update endpoints
3. **Option B: Helm** — `helm install` with the values file
4. **Option C: ArgoCD** — apply the Application manifest
5. **Networking / Exposing the collector** — how to make `:4317` reachable from outside the cluster:
   - Tailscale: annotate the Service for Tailscale operator, or run Tailscale as sidecar
   - NodePort: change Service type, use `<node-ip>:30317`
   - LoadBalancer: cloud-provider dependent
6. **Grafana dashboard** — import the same `claude-code.json` from Phase 2 into the cluster's Grafana
7. **Verifying the deployment** — check collector health, send test OTLP data, verify in Prometheus/Loki

## Acceptance Criteria

- [ ] `kubectl apply -k k8s/base/` creates all resources without errors (after endpoint URLs are set)
- [ ] Collector pod reaches `Running` status and passes readiness probe
- [ ] `kubectl port-forward svc/otel-collector 4317:4317` + sending OTLP data → data appears in cluster Prometheus/Loki
- [ ] Helm values file works with `helm install cc-otel open-telemetry/opentelemetry-collector -f k8s/helm/values.yaml`
- [ ] ArgoCD Application manifest is syntactically valid
- [ ] `docs/k8s-deployment.md` covers all 3 deployment options and networking guidance
- [ ] Grafana dashboard JSON from Phase 2 works unchanged against k8s-hosted Prometheus/Loki

## Verification Steps

1. Apply manifests: `kubectl apply -k k8s/base/` (with test cluster endpoints configured)
2. Check pod: `kubectl get pods -n cc-otel` — collector pod is `Running` and `Ready`
3. Check health: `kubectl exec -n cc-otel deploy/otel-collector -- wget -qO- http://localhost:13133`
4. Port-forward: `kubectl port-forward -n cc-otel svc/otel-collector 4317:4317`
5. Set CC env vars to point to `localhost:4317`, run a CC session
6. Verify metrics in cluster Prometheus and events in cluster Loki
7. Import `claude-code.json` into cluster Grafana — all panels render

## Parallelization Notes

- **Depends on**: P1-T1 (collector config is the base), P3-T1 (docs should be done first)
- **Blocks**: Nothing (final phase)
- **Partial parallel start**: The k8s manifests themselves can be drafted as soon as P1-T1 is done — they just wrap the
  same collector config. Only the deployment guide and end-to-end testing need the full stack from earlier phases.
- **Can mock**: Use `kubectl apply --dry-run=client` to validate manifests without a live cluster.
