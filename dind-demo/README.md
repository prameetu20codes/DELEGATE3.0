# DinD Build & Push Demo

An end-to-end [Harness CI](https://developer.harness.io/docs/continuous-integration) pipeline that:

1. Starts a **Docker-in-Docker (DinD)** daemon as a `Background` step, then
2. Runs a `Run` step that **builds a Docker image and pushes it to Docker Hub**.

The build target is a tiny Alpine image defined in this repo, so the pipeline has
something real to build and publish.

---

## Repository layout

| File | What it is |
|------|------------|
| [`Dockerfile`](./Dockerfile) | Defines the image that gets built and pushed |
| [`hello.sh`](./hello.sh) | Entrypoint script baked into the image |
| [`test-local.sh`](./test-local.sh) | Build/push the image from your own machine (pre-flight test) |
| [`find-dockerfile.sh`](./find-dockerfile.sh) | Discovery script: locates the right Dockerfile in a repo with many |
| [`pipeline.yml`](./pipeline.yml) | The Harness CI pipeline (import-ready) |
| [`pool.yml`](./pool.yml) | Self-hosted VM runner pool config (defines `poolName`) |
| `README.md` | This document |

---

## The Dockerfile & the image being built

```dockerfile
FROM alpine:3.20

RUN apk add --no-cache curl

ARG BUILD_TIME=unknown
ENV BUILD_TIME=${BUILD_TIME}

WORKDIR /app
COPY hello.sh /app/hello.sh
RUN chmod +x /app/hello.sh

ENTRYPOINT ["/app/hello.sh"]
```

**What each part does:**

- `FROM alpine:3.20` — minimal (~7 MB) base image, keeps builds fast.
- `RUN apk add --no-cache curl` — installs `curl` to show a real layer being built (and gives the image a usable tool).
- `ARG BUILD_TIME` / `ENV BUILD_TIME` — a build argument passed in at build time (the pipeline sets it to the UTC timestamp of the build) and persisted into the running container's environment.
- `WORKDIR /app` + `COPY hello.sh` — copies the entrypoint script into the image and makes it executable.
- `ENTRYPOINT ["/app/hello.sh"]` — when the image runs, it executes `hello.sh`.

**Resulting image**

| Property | Value |
|----------|-------|
| Base | `alpine:3.20` |
| Registry | Docker Hub |
| Repository | `prameet2025/<REPO>` |
| Tags | `<+pipeline.sequenceId>` (build number) and `latest` |
| Entrypoint | `/app/hello.sh` |
| Behavior | Prints `Hello from prameet2025 DinD build! Built at: <timestamp>` |

Run it after a successful push:

```bash
docker run --rm prameet2025/<REPO>:latest
```

---

## How the pipeline works

```
CI Stage (self-hosted VM, privileged allowed)
│
├─ Background step: docker:dind
│    entrypoint: dockerd-entrypoint.sh   (starts the Docker daemon)
│    privileged: true
│
└─ Run step: docker:latest
     DOCKER_HOST=tcp://localhost:2375    (talk to the DinD daemon)
     1. wait for the daemon to be ready
     2. docker login  (PAT from Harness secret `docker_pat`)
     3. docker build  (tags: build number + latest)
     4. docker push   (both tags)
```

Key design choices:

- **Self-hosted VM infrastructure** — DinD needs a **privileged** container, which
  Harness Cloud does not allow. The stage uses `infrastructure.type: VM` pointing at
  the `poolName` from [`pool.yml`](./pool.yml).
- **`sharedPaths: [/var/run]`** — shares the Docker socket path between the DinD and
  Run containers.
- **`DOCKER_HOST=tcp://localhost:2375`** — the Run step's `docker` CLI connects to the
  DinD daemon over TCP.
- **Secret, not hardcoded** — the Docker Hub PAT is referenced with
  `<+secrets.getValue("docker_pat")>`; it never appears in YAML or logs.
- **`cloneCodebase: false`** — no external git repo; the build context is this folder's
  `Dockerfile`.

---

## Selecting the right Dockerfile (repo has many)

The pipeline **clones the whole repo**, which contains more than one Dockerfile:

- `dind-demo/Dockerfile`
- `sample-app/app/Dockerfile`

A `docker build .` at the repo root fails (`no such file or directory`) because there
is no Dockerfile there. Discovery is built **into the Build and Push step itself**: it
scans the repo and selects a Dockerfile under `TARGET_DIR` (pipeline default:
`dind-demo`), derives the build context, then builds:

```bash
docker build -f "$DOCKERFILE" ... "$CONTEXT"
```

To build a different image, change the `TARGET_DIR` env var on the Build and Push step
(e.g. `sample-app/app`) — no other edits needed.

The standalone [`find-dockerfile.sh`](./find-dockerfile.sh) contains the same logic
(with an extra `DOCKERFILE_PATH` override) for running the discovery locally.

Run it locally to see what it picks:

```bash
cd <repo-root>
TARGET_DIR=dind-demo sh dind-demo/find-dockerfile.sh
```

## Usage

### 1. Pre-flight: test locally

Proves your Docker Hub credentials and the build work before wiring into Harness.

```bash
cd dind-demo
chmod +x hello.sh test-local.sh
export DOCKER_PASSWORD='dckr_pat_your_rotated_token'
./test-local.sh myapp          # builds & pushes prameet2025/myapp:local-test
```

### 2. Create the Harness secret

Account/Project → **Secrets** → **+ New Secret → Text**
- Secret ID: `docker_pat`
- Value: your Docker Hub PAT

### 3. Set up self-hosted VM build infrastructure

Install the Harness **Delegate + Runner**, then provide [`pool.yml`](./pool.yml)
(edit the driver block for your environment). The `name:` value is your **poolName**.
Docs: <https://developer.harness.io/docs/category/set-up-build-infrastructure>

### 4. Import the pipeline

Edit the `<PLACEHOLDERS>` in [`pipeline.yml`](./pipeline.yml)
(`<ORG>`, `<PROJECT>`, `<POOL_NAME>`, `<REPO>`), then in Harness:
**Pipelines → Create a Pipeline → Inline → Edit YAML**, paste, **Save**, **Run**.

---

## Security notes

- **Rotate any PAT you have pasted into chat or committed.** Treat it as compromised.
- Never commit real tokens. `docker_pat` lives only in Harness Secrets.
- `--password-stdin` is used for `docker login` so the token is not visible in the
  process list or build logs.
