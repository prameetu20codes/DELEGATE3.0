# Harness L3.0 — podinfo Deploy (Native Helm, deploy-only, public image)

A second sample for deploying an application through Harness with your existing
L3.0 / 3.3.1 delegates — **deploy-only** and using the **Native Helm** deployment
type. There is **no CI/build**: we deploy the public
[`stefanprodan/podinfo`](https://hub.docker.com/r/stefanprodan/podinfo) image
(pinned to `6.14.0`) via a Helm chart, and Harness runs `helm upgrade --install`.

## What's in here

```
podinfo-app/
├── chart/                       # A real Helm chart (rendered by the helm binary)
│   ├── Chart.yaml
│   ├── values.yaml              # default values (image overridden by Harness)
│   └── templates/
│       ├── configmap.yaml       # podinfo config (PODINFO_* env vars)
│       ├── deployment.yaml      # Deployment (health probes, metrics annotations)
│       ├── service.yaml         # Service (ClusterIP)
│       └── hpa.yaml             # HorizontalPodAutoscaler
└── harness/
    ├── values-harness.yaml      # Harness override: image <- <+artifact.image>
    ├── 01-service.yaml          # Harness Service (NativeHelm + HelmChart manifest)
    ├── 02-environment.yaml      # Environment (podinfo dev)
    ├── 03-infrastructure.yaml   # Infrastructure Definition (NativeHelm)
    └── 04-pipeline.yaml         # CD-only pipeline (HelmDeploy / HelmRollback)
```

## Native Helm vs plain Kubernetes (what changed)

| Aspect | Kubernetes (before) | Native Helm (now) |
|---|---|---|
| Manifests | K8s YAML + Harness Go-templating (`{{.Values.x}}` + `values.yaml`) | A real **Helm chart** rendered by the `helm` binary |
| Service type | `Kubernetes` | `NativeHelm` |
| Manifest type | `K8sManifest` | `HelmChart` (`folderPath` + `helmVersion: V3`) |
| Infra `deploymentType` | `Kubernetes` | `NativeHelm` |
| Deploy step | `K8sRollingDeploy` | `HelmDeploy` |
| Rollback step | `K8sRollingRollback` | `HelmRollback` |
| Image injection | `<+artifact.image>` in the Harness values file | Harness override `values-harness.yaml` passed to `helm -f` |
| Release tracking | Harness release secret | native **Helm release** (`helm list`) |

> Templating note: the chart uses standard **Helm/Sprig** semantics
> (`.Release.Name`, `| quote`, `range`, `toYaml`), **not** Harness Go-templating.
> Harness only resolves `<+...>` expressions inside `harness/values-harness.yaml`.

## Kubernetes workloads produced

| Workload | Kind | Source template |
|---|---|---|
| App config | ConfigMap (env) | `chart/templates/configmap.yaml` |
| podinfo | Deployment | `chart/templates/deployment.yaml` |
| Service | Service (ClusterIP) | `chart/templates/service.yaml` |
| Autoscaler | HorizontalPodAutoscaler | `chart/templates/hpa.yaml` |

## Reused (no need to recreate)

Reuses the connectors already created for `sample-app`:

| Connector | Identifier | Used for |
|---|---|---|
| Docker Hub | `dockerhub` | registry lookup of the public podinfo tag |
| GitHub | `github_connector` | fetching the chart from your repo |
| K8s Deploy Cluster | `k8s_connector` | running `helm` against the cluster |

No new secrets are required (the image is public). Also make sure the deploy
delegate has the **`helm` (v3) binary available** — the L3.0 build/runtime images
include it, but a custom delegate image may need it added.

## Placeholders to replace

Search-and-replace across `podinfo-app/` before creating anything:

| Placeholder | Meaning | Example |
|---|---|---|
| `<ORG_ID>` | Harness org identifier | `default` |
| `<PROJECT_ID>` | Harness project identifier | `sample_app_demo` |
| `<GIT_REPO_NAME>` | Repo you push this bundle to | `delegate-sample-app` |

> The Service points `folderPath: podinfo-app/chart` and
> `valuesPaths: podinfo-app/harness/values-harness.yaml`, so keep this folder at
> `podinfo-app/` in the repo. If you relocate it, update those paths in `01-service.yaml`.

## Step 1 — Push to your repository

From the `DELEGATE3.0` workspace root:

```bash
git checkout -b podinfo-app
git add podinfo-app
git commit -m "Add Harness L3.0 podinfo Native Helm deploy bundle (public image)"
git push -u origin podinfo-app
```

## (Optional) Validate the chart locally before pushing

```bash
helm lint podinfo-app/chart
helm template podinfo podinfo-app/chart -f podinfo-app/chart/values.yaml
```

## Step 2 — Create the Harness resources (in order)

Dependency order: service → environment → infrastructure → pipeline. Connectors
are already in place from `sample-app`. Create these in the **Harness UI** (paste
each YAML) or via the **Harness MCP** in Cursor — ask me to run:

1. `harness_create` resource_type `service` — `01-service.yaml`
2. `harness_create` resource_type `environment` — `02-environment.yaml`
3. `harness_create` resource_type `infrastructure` — `03-infrastructure.yaml`
4. `harness_create` resource_type `pipeline` — `04-pipeline.yaml`
   (body sent as `{ yamlPipeline: "<contents of 04-pipeline.yaml>" }`)

## Step 3 — Run it

Trigger the `Podinfo Deploy` pipeline. Harness runs `helm upgrade --install`,
creating the Deployment, Service, HPA, and ConfigMap in namespace `podinfo-dev`,
pulling `stefanprodan/podinfo:6.14.0`.

## Verify the deployment

```bash
kubectl get all,configmap,hpa -n podinfo-dev
helm list -n podinfo-dev                       # confirm the native Helm release
kubectl port-forward -n podinfo-dev svc/podinfo-svc 8080:80
# then open http://localhost:8080  (podinfo UI, /healthz, /readyz, /metrics)
```

## Bumping the image later

The tag is pinned in `01-service.yaml`. To deploy a newer podinfo, edit
`tag: 6.14.0` to the version you want and re-run the pipeline (or switch the
artifact `tag` to a runtime input to choose at run time). The chart's own default
`image` in `chart/values.yaml` is only used if you run `helm` outside Harness.
