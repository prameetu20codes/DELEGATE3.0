# Harness Delegate 3.0 (L3.0) — Knowledge Transfer

A summary of the work done exploring **Harness Delegate 3.0 / "Arnold" L3.0**: what was set up,
how it behaves, the issues encountered, and how they were resolved. Intended as a KT reference
for the team getting started with the new delegate.

---

## 1. Objective

Evaluate the new **Harness Delegate 3.0** in a NextGen setup and prove out an end-to-end flow:
1. Install the new lightweight delegate.
2. Understand the difference between **containerless** and **container/build** execution.
3. Build and deploy a **multi-container** Kubernetes app through a Harness CI + CD pipeline.

**Harness environment used:** NextGen on `harness-cxe.harness.io` (CXE account). Target cluster: a
GKE cluster (`harness-test`, `us-central1`) plus a standalone GCP VM for the Docker-based delegate.

---

## 2. What was done

### a. Delegate 3.0 install (Kubernetes)
- Installed the new delegate from `github.com/harness/delegate-kubernetes-manifest`.
- Image: `harness/delegate:3.3.1` (the new L3.0 runner, **not** the classic Java delegate).
- Very small footprint (~256 Mi) and a simple HTTP health endpoint on **port 3000 (`/health`)**.
- Namespace `harness-delegate-ng`, cluster-admin RBAC, token-based registration.

### b. A second "build" delegate
- Created a second delegate variant (`harness-delegate-build-ng.yaml`, namespace `harness-delegate-build`,
  tag `container-build`) with the intent to carry external tooling (docker, git, etc.).
- **Key realization:** on a *Kubernetes* delegate, CI steps already run as **build pods / containers**
  (each step runs on an image), so a separate "tools" delegate adds little value there. External tooling
  matters for the **Docker/VM delegate**, not the K8s one.

### c. Delegate 3.0 on a GCP VM (Docker build infra)
- Provisioned a GCP VM, SSH'd in from macOS, and ran the delegate directly as a binary
  (`./delegate server --env-file config.env`).
- Confirmed runner version 3.3.1 starting the HTTP server on `:3000` and registering `/health`.
- Ran pipelines in **containerless mode** on this delegate, then in **Docker mode** for build/push.

### d. Sample multi-container app + CI/CD pipeline
- Built a self-contained sample (`sample-app/`): a zero-dependency Node.js app + nginx sidecar,
  templated K8s workloads (Deployment with 2 containers, Service, HPA, ConfigMaps, Secret).
- Harness pipeline: **CI** (unit test → build & push image to Docker Hub) → **CD** (K8s rolling deploy).
- Public image + artifact registered in Harness so the deploy pulls the exact tag CI produced.

---

## 3. Key findings / learnings

1. **L3.0 is a lightweight runner.** Much smaller than the classic delegate (~256 Mi vs ~2 Gi),
   Go-based, health on `:3000/health`, dependencies largely provided by Harness at runtime.
2. **Containerless vs container execution:**
   - K8s delegate → CI steps always run as **build pods (containers on images)**.
   - VM/Docker delegate → needs a **running Docker daemon** for build steps; can also run
     containerless steps directly on the host.
3. **Two-delegate split is only useful across execution *types*** (K8s farm vs Docker VM), not as
   "plain + tools" on the same K8s cluster.
4. **K8s connector credential type is the #1 gotcha:**
   - Use `InheritFromDelegate` **only** when a delegate runs as a pod *inside* the target cluster.
   - Otherwise use `ManualConfig` (masterUrl + service-account token + CA cert). You cannot select a
     delegate that isn't in the cluster for an inherit-based connector.
5. **For an external cluster,** create a long-lived (non-expiring) service-account token and pass
   masterUrl / token / CA into the connector (helper in `test.sh`).
6. **Manifest hygiene for Harness Go templating:** avoid characters that a comment-strip can mangle
   (e.g. a `#` hex color in a value broke ConfigMap rendering) and keep **one workload per YAML file**.

---

## 4. Issues faced & how they were resolved

| # | Issue (symptom) | Root cause | Fix |
|---|---|---|---|
| 1 | Build & Push step failing on the pipeline | Delegate/build infra setup on the runner | Corrected the delegate/build configuration; build succeeded |
| 2 | `docker host unix:///var/run/docker.sock is not reachable` on the VM delegate | No Docker daemon installed/running on the VM | Installed and started Docker on the VM |
| 3 | Port `:3000` already in use / multiple delegate processes | A previous delegate process was still running | Killed the stale process, restarted cleanly (watch for duplicate `sudo nohup` processes) |
| 4 | CI test step: `could not find any files matching the provided report path` (junit.xml) | Working dir / report path mismatch in the container | Made the step `cd` into the right folder and used a glob path (`**/junit.xml`) for the JUnit report |
| 5 | K8s connector **test connection** failed: `Failed to parse CA Certificate … Incomplete data` | CA cert value truncated/malformed when pasted | Re-supplied a complete, valid X.509 CA cert (or omit CA if the API server cert is publicly trusted) |
| 6 | Pod event: `Unable to retrieve image pull secret (…-dockercfg)` | Image pull secret referenced but not needed for a public image | Harmless for public images; pull secret only needed for private registries |
| 7 | **Only one ConfigMap created** though two were defined; then `configmap "sample-app-config" not found` | Harness wasn't rendering/creating all workloads — traced to (a) multiple workloads sharing a file and (b) a value (`#` hex color) breaking ConfigMap rendering | **Split each workload into its own YAML file** (one workload per file) and **inlined/cleaned the ConfigMap data** (named color instead of `#hex`). All 6 resources then created. |

> The multi-resource issue (#7) was the biggest time-sink. Validated it by adding a second test
> Secret file and confirming both were picked up once the manifests were split and cleaned.

---

## 5. Recommendations for the team

- Prefer **L3.0 (3.3.1)** for new delegates — lighter and simpler than the classic delegate.
- Decide delegate topology by **execution type**: K8s delegate for in-cluster CI/CD; a **VM + Docker**
  delegate when you need host-level Docker builds.
- For any external cluster, standardize on **`ManualConfig` + non-expiring SA token + CA cert**, and
  always run **Test Connection** before wiring pipelines.
- **One Kubernetes workload per manifest file**, and keep values simple/YAML-safe to avoid
  render-time surprises.
- Register the built image as a **Harness artifact** and deploy the exact CI-produced tag.

---

## 6. Reference files in this repo

- `harness-delegate-3.0.yaml` — L3.0 deploy delegate (K8s).
- `harness-delegate-build-ng.yaml` — L3.0 build delegate (K8s, `container-build` tag).
- `harness-delegate-classic-3.0.yaml` — classic delegate variant (with auto-upgrader).
- `test.sh` — GKE credentials + long-lived SA token/CA helper for the K8s connector.
- `sample-app/` — the multi-container app, manifests, and CI+CD pipeline (see `sample-app/README.md`).
