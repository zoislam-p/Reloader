# Reloader UBI9 Local Validation Report

**Status:** Local functional validation passed with documented warnings

**Test date:** July 30, 2026

**Repository:** `https://github.com/zoislam-p/Reloader.git`

**Branch:** `feature/ubi9-reloader-migration`

**Source commit tested:** `b1263fe6c22a5699e4262e5b79af5823062334d9`

## Executive summary

The Reloader UBI9 path was built and tested locally. The final image was
confirmed as Linux AMD64, RHEL/UBI 9.8-based, non-root, and configured with the
expected `/manager` entrypoint and port. The existing upstream Helm chart
passed lint and rendered correctly with the local UBI image.

Reloader was then installed into a dedicated Minikube cluster. A ConfigMap
change caused an annotated test Deployment to advance from revision 1 to
revision 2 and replace its pod. Reloader logs explicitly confirmed the
detected ConfigMap change and Deployment update.

This proves the core Reloader behavior in the local environment. SPS,
enterprise scanning/signing, IBM registry, and Rancher/RKE2 validation remain
external or future gates.

## Scope and approach

Reloader already contains an upstream-maintained UBI9 path:

- `Dockerfile` builds `/manager`;
- `Dockerfile.ubi` creates a reduced UBI-derived runtime;
- `ubi-build-files-amd64.txt` selects required UBI runtime content; and
- `deployments/kubernetes/chart/reloader` is the existing Helm chart.

No replacement Helm chart or operator was created. Reloader is itself a
Kubernetes controller Deployment; it is not installed through a separate
Operator Lifecycle Manager operator.

## Environment

| Component | Observed value |
|---|---|
| Docker client/server | 28.0.1 / 28.0.1 |
| Docker host | Linux ARM64 through Docker Desktop |
| Target image | Linux AMD64 |
| Minikube profile | `reloader-ubi9` |
| Kubernetes server | v1.32.0, Linux ARM64 |
| kubectl client | v1.32.3 |
| Helm | v3.6.2 |

The AMD64 image ran under Docker Desktop's cross-platform emulation on the
ARM64 Minikube node. Native AMD64 node validation remains required in
Rancher/RKE2 or another AMD64 cluster.

## Test results

| Test | Result | Evidence |
|---|---|---|
| AMD64 source-image build | PASS | Image `sha256:bfc2178796c861694729ec3a6e95cdddf7d797cd473f723655fc5446feb1b869` |
| UBI9 runtime build | PASS | Image `sha256:78803fd6206fdbaa5fde4a6ad00cfb5e4c2f9c5654eb8d1e2a75c7d4965ba484` |
| Runtime OS/architecture | PASS | `linux/amd64`; RHEL release 9.8 |
| Manager binary | PASS | ELF x86-64, statically linked |
| Image security metadata | PASS | User `65532:65532`; entrypoint `/manager` |
| Image port | PASS | `9090/tcp` exposed |
| RPM database retained | PASS | `/var/lib/rpm/rpmdb.sqlite` present |
| Helm lint | PASS | One chart linted, zero failures |
| Helm template | PASS | Local image, `Never` pull policy, non-root settings rendered |
| Helm installation | PASS | Release status `deployed`, revision 1 |
| Reloader readiness | PASS | Deployment 1/1; pod Running; zero restarts |
| ConfigMap functional test | PASS | Deployment revision 1 → 2; pod replaced |
| Controller log evidence | PASS | Log confirmed detected ConfigMap change and Deployment update |
| Go/unit tests | NOT RUN | Go CLI was not installed on the test workstation |
| Upstream full E2E suite | NOT RUN | Focused UBI functional test was run; full suite requires additional dependencies/time |
| SPS build and gates | NOT RUN | IBM SPS access/configuration not available locally |
| Rancher/RKE2 | NOT RUN | Requires access to the target environment and reachable registry |

## Image evidence

```text
imageId=sha256:78803fd6206fdbaa5fde4a6ad00cfb5e4c2f9c5654eb8d1e2a75c7d4965ba484
os=linux
architecture=amd64
configuredUser=65532:65532
entrypoint=["/manager"]
exposedPort=9090/tcp
size=65967594 bytes
release=Red Hat Enterprise Linux release 9.8 (Plow)
binary=ELF 64-bit LSB executable, x86-64, statically linked
rpmDatabase=/var/lib/rpm/rpmdb.sqlite
```

The image has no repository digest because it was loaded locally rather than
pushed to a content-addressed enterprise registry.

## Helm and Kubernetes evidence

The existing chart rendered these relevant values:

```text
image: reloader-local:ubi9
imagePullPolicy: Never
runAsNonRoot: true
runAsUser: 65534
```

The chart-level pod security context overrides the image's configured UID at
runtime. Both values are non-root.

Observed Reloader workload:

```text
deployment/reloader-reloader  READY 1/1  image=reloader-local:ubi9
pod/reloader-reloader-85cb84d69d-vtdr7  Running  restarts=0
```

## Functional evidence

Initial state:

```text
initialPod=reloader-test-app-665dcb8d44-hhf8n
initialRevision=1
```

After changing `reloader-test-config`:

```text
newPod=reloader-test-app-689b9b69d6-6qqx9
newRevision=2
```

Controller evidence:

```text
Changes detected in 'reloader-test-config' of type 'CONFIGMAP' in namespace
'reloader-test'; updated 'reloader-test-app' of type 'Deployment' in namespace
'reloader-test'
```

The reusable script was run again and also passed, advancing revision 3 to 4
and replacing the application pod a second time.

## Findings and warnings

### Upstream UBI flow already exists

This repository is different from OCM: UBI9 support is already present
upstream. The correct approach is to preserve that logic and add only the SPS
contract, reproducible tests, or policy changes that are actually required.

### Apple Silicon local build needs explicit handling

The first direct UBI command failed because BuildKit tried to resolve
`reloader-local:builder` from Docker Hub:

```text
pull access denied, repository does not exist
```

For the successful local cross-build, the source image was pushed to a
localhost-only registry and `BUILDPLATFORM=linux/amd64` was supplied
explicitly. No external credentials were used.

SPS is expected to use registry-backed build artifacts, but its exact
multi-stage contract must be confirmed before adding Makefile wrappers.

### Dockerfile warnings

BuildKit reported:

- uppercase stage name `SRC`; and
- no valid default for required `BUILDER_IMAGE`.

These are warnings, not build failures. They should be tracked and evaluated
against SPS parsing and policy.

### Shell-free runtime behavior

The final image intentionally does not include common utilities such as
`/bin/cat` or `/usr/bin/id`. Evidence was extracted from a stopped container
instead. Running `/manager` outside Kubernetes fails while creating an
in-cluster client; Kubernetes startup is the valid smoke test.

## Files added for repeatable testing

| File | Purpose |
|---|---|
| `deployments/local-test/values-ubi9.yaml` | Local Helm image override |
| `deployments/local-test/reload-test.yaml` | ConfigMap and annotated test Deployment |
| `hack/verify-ubi9-image.sh` | Image platform, UBI, binary, user, and entrypoint checks |
| `hack/test-local-reload.sh` | Repeatable ConfigMap-to-rollout functional test |
| `docs/RELOADER-UBI9-LOCAL-TESTING-GUIDE.md` | Exact execution and cleanup commands |
| `docs/RELOADER-UBI9-LOCAL-VALIDATION-REPORT.md` | Evidence and limitations |

## Remaining work and blockers

- Confirm the SPS-required Makefile target names and image variables.
- Decide whether SPS builds the normal source image and UBI image in one stage
  or passes a registry-backed builder image between stages.
- Run Go unit tests when the approved Go toolchain is available.
- Run the upstream full Kind E2E suite when its dependencies are available.
- Run IBM SBOM, vulnerability, malware, signing, and provenance gates.
- Push the image to an approved registry.
- Deploy to an AMD64 Rancher/RKE2 cluster and repeat the ConfigMap rollout
  test without emulation.
- Confirm whether the UBI-derived scratch runtime meets the project's exact
  base-image policy.

## Manager-ready summary

The existing Reloader UBI9 image path was successfully built and validated
locally for AMD64. The upstream Helm chart installed the image into Minikube,
and the core function worked: changing a ConfigMap caused Reloader to roll the
annotated application and replace its pod. We also added reusable scripts and
manifests so the same evidence can be reproduced. The remaining work is SPS
integration, enterprise security gates, and native AMD64 Rancher/RKE2
validation.
