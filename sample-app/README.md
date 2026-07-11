# Harness L3.0 Sample App — Multi-container Kubernetes deployment

A complete, self-contained sample for deploying a **multi-container** Kubernetes
application through Harness (using your existing L3.0 / 3.3.1 delegates), with a
**CI + CD** pipeline: build & push the image to Docker Hub, then rolling-deploy it.

## What's in here

```
sample-app/
├── app/                      # Buildable source (zero-dependency Node.js) + Dockerfile
│   ├── server.js
│   ├── test.js               # produces junit.xml for the CI test step
│   ├── package.json
│   └── Dockerfile            # public base image (node:20-alpine)
├── harness/
│   ├── manifests/            # Harness-templated K8s workloads (Go templating + values.yaml)
│   │   ├── values.yaml
│   │   ├── configmap.yaml    # 2 ConfigMaps (app env + nginx proxy config)
│   │   ├── deployment.yaml   # Deployment with 2 containers (app + nginx sidecar)
│   │   ├── service.yaml      # Service
│   │   └── hpa.yaml          # HorizontalPodAutoscaler
│   ├── 01-secrets.yaml       # Docker Hub + GitHub tokens
│   ├── 02-connectors.yaml    # Docker Hub, GitHub, 2x K8s (deploy + build)
│   ├── 03-service.yaml       # Harness Service (artifact + manifests)
│   ├── 04-environment.yaml   # Environment (dev)
│   ├── 05-infrastructure.yaml# Infrastructure Definition (KubernetesDirect)
│   └── 06-pipeline.yaml      # CI + CD pipeline
└── README.md
```

The **Deployment** runs two containers per pod:
- `web` — the image built by CI and pushed to your Docker Hub (`<DOCKERHUB_USER>/sample-app`).
- `proxy` — the **public** `nginx:1.27-alpine` image, reverse-proxying to the app.

This gives you Deployment + Service + HPA + ConfigMap workloads, a multi-container
pod, and both a **built** artifact (registered in Harness) and a public sidecar image.

## Kubernetes workloads produced

| Workload | Kind | Source manifest |
|---|---|---|
| App config | ConfigMap (env) | `manifests/configmap.yaml` |
| Proxy config | ConfigMap (volume) | `manifests/configmap.yaml` |
| App + sidecar | Deployment (2 containers) | `manifests/deployment.yaml` |
| Service | Service (ClusterIP) | `manifests/service.yaml` |
| Autoscaler | HorizontalPodAutoscaler | `manifests/hpa.yaml` |

## Placeholders to replace

Search-and-replace these across `harness/` before creating anything:

| Placeholder | Meaning | Example |
|---|---|---|
| `<ORG_ID>` | Harness org identifier | `default` |
| `<PROJECT_ID>` | Harness project identifier | `sample_app_demo` |
| `<DOCKERHUB_USER>` | Docker Hub username / image namespace | `prameet` |
| `<GIT_ORG_URL>` | GitHub account URL | `https://github.com/prameet` |
| `<GIT_USER>` | GitHub username | `prameet` |
| `<GIT_REPO_NAME>` | Repo you push this bundle to | `delegate-sample-app` |
| `<REPLACE_WITH_DOCKERHUB_TOKEN>` | Docker Hub access token | (secret) |
| `<REPLACE_WITH_GITHUB_TOKEN>` | GitHub PAT (repo read) | (secret) |

> The pipeline expects this whole folder to live at `sample-app/` in your repo,
> since the manifest paths, Dockerfile path, and build context are all
> `sample-app/...`. If you put it at the repo root instead, drop the `sample-app/`
> prefix in `03-service.yaml` and `06-pipeline.yaml`.

## Step 1 — Push to your repository

From the `DELEGATE3.0` workspace root:

```bash
git checkout -b sample-app
git add sample-app
git commit -m "Add Harness L3.0 multi-container sample app"
# point origin at your new/target repo, then:
git push -u origin sample-app
```

Or copy the `sample-app/` folder into a fresh repo and push that.

## Step 2 — Create the Harness resources (in order)

Dependency order matters — secrets first, then connectors, then service/env/infra,
then the pipeline. Create them either in the **Harness UI** (paste each YAML) or
via the **Harness MCP** in Cursor. With the MCP authenticated, ask me to run:

1. `harness_create` resource_type `secret` — the two secrets in `01-secrets.yaml`
2. `harness_create` resource_type `connector` — the four connectors in `02-connectors.yaml`
   - then `harness_execute` action `test_connection` on each to verify the delegates respond
3. `harness_create` resource_type `service` — `03-service.yaml`
4. `harness_create` resource_type `environment` — `04-environment.yaml`
5. `harness_create` resource_type `infrastructure` — `05-infrastructure.yaml`
6. `harness_create` resource_type `pipeline` — `06-pipeline.yaml`
   (body sent as `{ yamlPipeline: "<contents of 06-pipeline.yaml>" }`)

## Step 3 — Run it

Trigger the `Sample App CICD` pipeline (branch `main`). It will:
1. Run the unit test and publish the JUnit report.
2. Build `sample-app/app/Dockerfile` and push `<DOCKERHUB_USER>/sample-app:<buildNumber>` + `:latest`.
3. Roll out the Deployment, Service, HPA, and ConfigMaps into namespace `sample-app-dev`.

The CD stage deploys the exact tag CI just pushed (`<+pipeline.sequenceId>`).

## Verify the deployment

```bash
kubectl get all,configmap,hpa -n sample-app-dev
kubectl port-forward -n sample-app-dev svc/sample-app-svc 8080:80
# then open http://localhost:8080
```

## Notes on the two delegates

- **Deploy** uses connector `k8s_connector` → delegate `kubernetes-delegate-linux-ng`.
- **Build** uses connector `k8s_build_connector` → delegate tag `container-build`
  (namespace `harness-delegate-build`), so CI build pods run on the build farm.

If your Docker Hub repo is **private**, Harness auto-generates the image pull
secret from the `dockerhub` connector (`<+artifact.imagePullSecret>` in
`values.yaml`). For a **public** repo it's harmless and unused.
