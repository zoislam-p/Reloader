# Reloader UBI9 Local Testing Guide

## Purpose

This runbook validates the Reloader UBI9 image locally on an AMD64 target,
installs it through the existing upstream Helm chart, and proves the core
Reloader function: a ConfigMap change triggers a workload rollout.

Run commands from the repository root—the directory containing `Dockerfile`,
`Dockerfile.ubi`, `Makefile`, `deployments/`, and `hack/`.

## What is being tested

1. The normal source image builds for `linux/amd64`.
2. `Dockerfile.ubi` produces a `linux/amd64` runtime.
3. The runtime contains RHEL/UBI 9 release evidence and an AMD64 `/manager`.
4. Image metadata preserves the non-root user, entrypoint, and port.
5. The existing Helm chart lints and renders with the local UBI image.
6. Reloader starts in Kubernetes.
7. Changing a ConfigMap replaces the annotated application's pod.
8. Reloader logs confirm that it detected the change.

## Prerequisites

- Docker Desktop with Buildx
- `kubectl`
- Helm
- Minikube
- Sufficient network access to pull Go, UBI, registry, Kubernetes, and
  BusyBox images

The target image is AMD64 even when the development laptop is Apple Silicon.

## 1. Record the source

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Save the commit SHA with the evidence. Do not mix unrelated uncommitted code
changes into a test result.

## 2. Build the AMD64 source image

`Dockerfile.ubi` expects a source image that already contains `/manager`.

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t reloader-local:builder \
  -f Dockerfile \
  .
```

## 3. Make the source image resolvable to BuildKit

On Apple Silicon, the upstream `Dockerfile.ubi` source stage uses
`${BUILDPLATFORM}`. A Docker-loaded local image may therefore be treated as a
registry reference rather than resolved from the local image store.

Use a localhost-only registry for local validation:

```bash
docker run -d \
  --name reloader-local-registry \
  -p 127.0.0.1:5000:5000 \
  registry:2

docker tag \
  reloader-local:builder \
  localhost:5000/reloader-builder:test

docker push localhost:5000/reloader-builder:test
```

If the registry container already exists:

```bash
docker start reloader-local-registry
```

This registry is only a local test transport. It is not an SPS or production
registry and uses no IBM credentials.

## 4. Build the UBI9 image

Explicitly select AMD64 for the UBI target and source stage:

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILDPLATFORM=linux/amd64 \
  --build-arg BUILDER_IMAGE=localhost:5000/reloader-builder:test \
  --load \
  -t reloader-local:ubi9 \
  -f Dockerfile.ubi \
  .
```

The build currently emits two upstream warnings:

- the `SRC` stage name is uppercase; and
- `BUILDER_IMAGE` has no valid default.

They do not fail the build, but they should be evaluated before SPS
integration.

## 5. Validate the final image

```bash
IMAGE=reloader-local:ubi9 \
EXPECTED_PLATFORM=linux/amd64 \
bash hack/verify-ubi9-image.sh
```

The script verifies:

- `linux/amd64`;
- image user `65532:65532`;
- `/manager` entrypoint;
- RHEL/UBI major version 9; and
- an x86-64 manager binary.

The final image is intentionally shell-minimal. Do not treat missing
`/bin/bash`, `/bin/cat`, or `/usr/bin/id` as a failure. The script copies
evidence from a stopped container instead of requiring a shell.

Running `/manager` without Kubernetes configuration is also not a useful
standalone health check; it correctly exits because it cannot create an
in-cluster Kubernetes client.

## 6. Validate the existing Helm chart

```bash
helm lint deployments/kubernetes/chart/reloader

helm template reloader \
  deployments/kubernetes/chart/reloader \
  --namespace reloader \
  --values deployments/local-test/values-ubi9.yaml
```

Confirm that the rendered Deployment uses:

- `reloader-local:ubi9`;
- `imagePullPolicy: Never`;
- `runAsNonRoot: true`; and
- the chart's configured runtime UID.

## 7. Create the local cluster

```bash
minikube start -p reloader-ubi9 --driver=docker
minikube image load reloader-local:ubi9 -p reloader-ubi9
```

The dedicated profile prevents commands from accidentally targeting an
existing corporate or cloud Kubernetes context.

## 8. Install Reloader with Helm

```bash
kubectl --context reloader-ubi9 create namespace reloader \
  --dry-run=client -o yaml |
kubectl --context reloader-ubi9 apply -f -

helm upgrade --install reloader \
  deployments/kubernetes/chart/reloader \
  --kube-context reloader-ubi9 \
  --namespace reloader \
  --values deployments/local-test/values-ubi9.yaml \
  --wait \
  --timeout 5m
```

Verify:

```bash
helm status reloader --kube-context reloader-ubi9 -n reloader
kubectl --context reloader-ubi9 -n reloader get deployment,pod -o wide
kubectl --context reloader-ubi9 -n reloader logs deployment/reloader-reloader
```

## 9. Run the functional reload test

```bash
KUBE_CONTEXT=reloader-ubi9 bash hack/test-local-reload.sh
```

The script:

1. checks that the Reloader Deployment is available;
2. applies the test namespace, ConfigMap, and annotated Deployment;
3. records the initial pod and revision;
4. changes the ConfigMap;
5. waits for the rollout;
6. confirms that the pod name changed and revision increased; and
7. checks the controller log for the detected ConfigMap change.

A passing result ends with:

```text
PASS: Reloader ConfigMap rollout
```

## 10. Collect evidence

```bash
docker image inspect reloader-local:ubi9
helm status reloader --kube-context reloader-ubi9 -n reloader
kubectl --context reloader-ubi9 -n reloader get deployment,pod -o wide
kubectl --context reloader-ubi9 -n reloader-test get deployment,pod -o wide
kubectl --context reloader-ubi9 -n reloader logs \
  deployment/reloader-reloader --since=10m
```

Record pass/fail results, source commit, image ID, exact commands, warnings,
limitations, and unresolved external gates.

## 11. Cleanup

```bash
helm uninstall reloader --kube-context reloader-ubi9 -n reloader
kubectl --context reloader-ubi9 delete -f \
  deployments/local-test/reload-test.yaml
minikube delete -p reloader-ubi9
docker stop reloader-local-registry
```

Image removal is optional. Do not delete the cluster until screenshots or
additional evidence are complete.

## What this does not prove

Local testing does not prove:

- SPS build behavior;
- IBM registry push/pull;
- SBOM, vulnerability, malware, signing, or provenance gates;
- Rancher/RKE2 deployment on an AMD64 node;
- production scalability or upgrade behavior; or
- acceptance of the upstream UBI-derived scratch design.
