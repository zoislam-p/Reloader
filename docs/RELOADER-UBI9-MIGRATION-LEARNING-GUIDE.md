# Reloader UBI9 Migration — Learning and Execution Guide

Prepared for Gaurav  
Source repository: `zoislam-p/Reloader`  
Upstream: `stakater/Reloader`  
Reviewed upstream branch: `master`  
Reviewed revision: `b1733c54f9d1a0ac3f47195302d96bdc237f043d`

## 1. Purpose

This guide explains how to evaluate and implement the Reloader UBI9 image
migration using a disciplined, evidence-based approach:

1. understand the upstream project;
2. preserve original files;
3. make the smallest required image changes;
4. build and test the image;
5. add pipeline-facing Makefile targets only when required;
6. use the existing Helm chart;
7. deploy to a local Kubernetes cluster or Rancher/RKE2;
8. validate real Reloader behavior; and
9. record evidence, decisions, and blockers.

This is a learning guide. Understand how Reloader already works before making
changes.

## 2. What Reloader does

Reloader is a Kubernetes controller. Kubernetes does not automatically restart
an application when a referenced ConfigMap or Secret changes. Reloader watches
those resources and triggers a rollout of the workloads that depend on them.

Typical flow:

1. An application Deployment references a ConfigMap or Secret.
2. The Deployment opts in with a Reloader annotation.
3. Reloader watches the referenced resource.
4. The ConfigMap or Secret changes.
5. Reloader updates the workload pod template.
6. Kubernetes creates replacement pods with the new configuration.

Reloader is the application/controller. It is not installed through a separate
Kubernetes operator.

## 3. Reloader project structure

Reloader has a focused controller architecture:

- one primary image: `reloader`;
- one controller Deployment;
- one existing Helm chart;
- no separate Kubernetes operator installation; and
- no CRD is required for its basic annotation-driven behavior.

Upstream Reloader already contains:

- `Dockerfile` — builds the normal distroless image;
- `Dockerfile.ubi` — builds a UBI-derived image;
- `Makefile` — build, unit-test, end-to-end, image, manifest, and release
  targets;
- GitHub Actions that build both normal and UBI variants;
- `deployments/kubernetes/chart/reloader` — the existing Helm chart; and
- Kind-based end-to-end tests.

Therefore, the first task is not “replace everything with UBI9.” The first task
is to determine whether the existing UBI implementation satisfies the exact
Sovereign Core requirement.

## 4. Critical technical finding

The existing `Dockerfile.ubi` starts from a UBI9 image, assembles a reduced UBI
root filesystem, and copies that filesystem into a final `scratch` stage.

This creates an important acceptance question:

- If the requirement allows a UBI-derived scratch image with Red Hat package
  metadata, the existing approach may already be acceptable.
- If the requirement says the final runtime stage must literally use
  `registry.access.redhat.com/ubi9/ubi`, the current final `FROM scratch` stage
  may not satisfy it.

Do not change this design until the team confirms which interpretation is
required. Record the answer in the pull request and project documentation.

## 5. Repository setup

Clone your fork and enter its root directory:

```bash
git clone git@github.com:zoislam-p/Reloader.git
cd Reloader
git remote -v
git status
```

Confirm:

- `origin` points to `zoislam-p/Reloader`;
- `upstream` points to `stakater/Reloader`;
- the working tree is clean; and
- the expected upstream revision or approved release tag is checked out.

Create a feature branch:

```bash
git checkout -b feature/ubi9-reloader-migration
```

Do not work directly on `master`.

## 6. Preserve original files

Before changing a file, create the requested `.org` backup:

```bash
cp Dockerfile Dockerfile.org
cp Dockerfile.ubi Dockerfile.ubi.org
cp Makefile Makefile.org
```

Only back up a file that will actually be changed. Verify the copies:

```bash
cmp Dockerfile Dockerfile.org
cmp Dockerfile.ubi Dockerfile.ubi.org
cmp Makefile Makefile.org
```

The backups provide an easy comparison with upstream. They are not substitutes
for Git history.

## 7. Phase 1 — Dockerfile assessment

### Review `Dockerfile`

The normal image:

- uses a Go builder;
- compiles `/manager` with `CGO_ENABLED=0`;
- uses a distroless non-root runtime;
- runs as UID/GID `65532`; and
- exposes port `9090`.

Preserve the builder unless a requirement specifically changes it.

### Review `Dockerfile.ubi`

The UBI variant:

- receives a previously built image through `BUILDER_IMAGE`;
- uses a pinned UBI9 base by default;
- installs `binutils`;
- copies a selected UBI root filesystem;
- builds an RPM database for package traceability;
- uses `scratch` as the final stage;
- copies `/manager`; and
- runs as UID/GID `65532`.

### Decision checklist

Before editing, answer:

- Must the final stage literally be UBI9?
- Is a UBI-derived scratch image accepted?
- Is the pinned public UBI9 image approved?
- Must the production base use an internal registry mirror?
- Is UID `65532` accepted, or is UID `10001` required?
- Is the target only `linux/amd64`, or must upstream ARM64 behavior remain?
- Are `dnf update` and the additional `binutils` package approved?
- Must the image keep an RPM database for scanning?

### Minimal-change rule

Keep upstream logic whenever it already meets the requirement. Do not replace
the existing UBI packaging design without an approved technical reason.

If a strict UBI runtime is required, the likely design is:

1. keep the existing builder/static binary logic;
2. use an approved pinned UBI9 runtime;
3. copy `/manager` into the runtime;
4. preserve the non-root user, port, and entrypoint;
5. avoid unnecessary packages; and
6. document why the upstream UBI-derived scratch stage was changed.

## 8. Phase 2 — Build and image testing

### Build the normal image first

The existing UBI workflow expects a source image containing `/manager`.

Example:

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t reloader-local:builder \
  -f Dockerfile \
  .
```

### Build the UBI image

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILDER_IMAGE=reloader-local:builder \
  --load \
  -t reloader-local:ubi9 \
  -f Dockerfile.ubi \
  .
```

### Required image evidence

Save:

- build command and successful exit status;
- image ID;
- image digest if available;
- operating system and architecture;
- configured user;
- entrypoint;
- image size;
- package/RPM evidence required by the scanner; and
- source revision used for the build.

Example inspection:

```bash
docker image inspect reloader-local:ubi9 \
  --format 'id={{.Id}} os={{.Os}} arch={{.Architecture}} user={{.Config.User}} entrypoint={{json .Config.Entrypoint}} size={{.Size}}'
```

### Runtime checks

Verify:

- the image is Linux AMD64;
- it runs as the expected non-root UID;
- `/manager` exists and starts;
- the process does not require a writable root filesystem unless documented;
- port `9090` probes work after deployment; and
- the image does not contain unintended package-manager or build artifacts.

Do not assume `/bin/bash` exists in a scratch-based final image. Use image
metadata and Kubernetes runtime tests when a shell is unavailable.

## 9. Phase 3 — Makefile approach

Reloader already has upstream targets for:

- Go build;
- unit tests;
- lint;
- normal image build;
- multi-architecture image build;
- push and manifest;
- Kind end-to-end setup and tests;
- generated Kubernetes manifests; and
- load tests.

First compare the required SPS target contract with the existing Makefile.
Only add wrapper targets that the pipeline actually requires.

Potential wrapper targets, subject to the SPS contract:

- `pre-build` — validate tools, backups, Dockerfile policy, and Helm lint;
- `docker-build-ubi` — build the AMD64 UBI image through the existing
  two-image flow;
- `docker-test-ubi` — inspect metadata and perform runtime smoke tests;
- `helm-package` — lint and package the existing chart; and
- `deploy` — install the chart with an explicitly supplied image.

If these targets are added:

- label them as new wrapper targets;
- explain that they are not upstream targets;
- delegate to existing upstream behavior where possible;
- keep `Makefile.org` available;
- do not hardcode IBM credentials or namespaces; and
- make registry, tag, platform, chart version, engine, and context parameters.

## 10. Phase 4 — Pipeline

The upstream GitHub workflows already build both image variants:

- the normal image from `Dockerfile`;
- the UBI image from `Dockerfile.ubi`;
- AMD64 and ARM64 UBI platforms; and
- `-ubi` image tags.

Review these files before creating a new pipeline:

- `.github/workflows/pull_request.yaml`;
- `.github/workflows/push.yaml`;
- `.github/workflows/release.yaml`; and
- `.github/workflows/pull_request-helm.yaml`.

For SPS:

- call documented Makefile targets;
- use placeholders or injected variables;
- do not embed IBM credentials;
- leave signing, scanning, mirroring, and publishing to approved services;
- preserve upstream GitHub Actions unless replacement is explicitly required;
- document which upstream steps map to SPS stages.

## 11. Phase 5 — Helm

Reloader already has a Helm chart:

`deployments/kubernetes/chart/reloader`

Important image values:

- `image.repository`;
- `image.tag`;
- optional `image.digest`;
- `image.pullPolicy`;
- `global.imageRegistry`; and
- `global.imagePullSecrets`.

Do not create a replacement chart. Use a small values override for the UBI
image.

Example local values:

```yaml
image:
  repository: reloader-local
  tag: ubi9
  pullPolicy: Never

reloader:
  watchGlobally: true
```

For Rancher/RKE2, use a registry reachable by all nodes and normally set
`IfNotPresent`. Never commit registry passwords or pull tokens.

Validate the chart:

```bash
helm lint deployments/kubernetes/chart/reloader
helm template reloader deployments/kubernetes/chart/reloader \
  --namespace reloader \
  --set image.repository=reloader-local \
  --set image.tag=ubi9 \
  --set image.pullPolicy=Never
```

## 12. Phase 6 — Kubernetes functional test

Image startup is not enough. Test the real Reloader function.

### Test design

Create:

- a test namespace;
- a ConfigMap containing a value;
- a Deployment that reads the ConfigMap;
- the annotation `reloader.stakater.com/auto: "true"`; and
- a simple container that stays running.

Record the initial pod name and Deployment rollout state. Change the
ConfigMap. Reloader should update the workload and Kubernetes should replace
the pod.

### Pass conditions

- Reloader Deployment is Ready.
- Reloader runs the UBI image.
- Reloader pod runs as non-root.
- Test application is Ready.
- ConfigMap update triggers a new rollout.
- Old and new pod names differ.
- Reloader logs show the detected change and rollout.
- No unexpected RBAC, admission, or image-pull failures occur.

Also run the existing upstream unit and Kind end-to-end tests when resources
allow. Preserve their results separately from the focused UBI smoke test.

## 13. Rancher/RKE2 validation

For Rancher:

1. push the image to a registry reachable by RKE2 nodes;
2. create an image pull secret if the registry is private;
3. use the existing Helm chart with the UBI repository/tag;
4. verify Deployment, Pod, service account, RBAC, events, probes, and logs in
   Rancher Explore;
5. run the ConfigMap rollout test; and
6. save evidence.

Reloader is installed directly into the target Kubernetes cluster as a
controller Deployment. No separate multicluster bootstrap flow is required.

## 14. Files likely to change

Do not treat this as a mandatory list. Modify only files required by the
approved design.

| File | Reason it might change |
|---|---|
| `Dockerfile.ubi` | Align final runtime with the accepted UBI9 requirement |
| `Dockerfile.ubi.org` | Backup before changing the UBI Dockerfile |
| `Makefile` | Add only required SPS wrapper targets |
| `Makefile.org` | Backup before changing the Makefile |
| Helm override file | Select the UBI image without changing chart defaults |
| Pipeline documentation/config | Map SPS stages to Makefile targets |
| Test script/manifests | Reproducible image and rollout validation |
| Migration README/report | Explain decisions, evidence, and blockers |

The normal `Dockerfile` should remain unchanged unless the approved design
requires it.

## 15. Files that should normally remain unchanged

- Go controller source;
- existing Helm templates;
- existing upstream unit and end-to-end tests;
- release workflows not in the SPS scope;
- default chart behavior; and
- ARM64 support, unless the new pipeline explicitly targets AMD64 without
  removing upstream compatibility.

## 16. Evidence checklist

Capture:

- branch and commit;
- changed-file list;
- original-file comparisons;
- successful Go/unit tests;
- successful Helm lint and template;
- normal image build result;
- UBI image build result;
- image ID, digest, architecture, user, entrypoint, and size;
- UBI/RPM or scanner evidence;
- Kubernetes Deployment and Pod status;
- exact image used by the Pod;
- initial and replacement test pod names;
- ConfigMap change;
- Reloader logs;
- Rancher screenshots if applicable;
- failures and fixes; and
- uncompleted IBM-controlled gates.

Never claim a production release based only on local validation.

## 17. Common mistakes to avoid

- Replacing the existing UBI design without confirming acceptance criteria.
- Inventing unnecessary operators, images, or multicluster installation steps.
- Creating a new Helm chart when one already exists.
- Using a local-only image name on Rancher.
- Using `imagePullPolicy: Never` on remote RKE2 nodes.
- Adding Makefile targets that no pipeline requires.
- Hardcoding IBM credentials, registry namespaces, or tokens.
- Removing upstream ARM64 behavior unnecessarily.
- Testing only that the container starts.
- Approving the work without proving that a ConfigMap change triggers a
  rollout.
- Committing kubeconfigs, Docker credentials, or private registry secrets.

## 18. Blockers and questions to record

- Is the existing UBI-derived scratch image accepted?
- Which exact UBI9 tag or digest is approved?
- Is a public Red Hat base allowed, or must it use an internal mirror?
- Is UID 65532 accepted?
- What exact SPS target names are mandatory?
- Which IBM registry and chart repository will be used?
- Which security scanner and signing service apply?
- Is only AMD64 required while upstream ARM64 is preserved?
- Is Rancher/RKE2 the formal acceptance environment?
- Which release tag should be used instead of upstream `master`?

## 19. Recommended work sequence

1. Confirm the accepted UBI runtime definition.
2. Select the approved upstream release tag.
3. Create the feature branch.
4. Back up only files that will change.
5. Run upstream tests before editing.
6. Make the minimal Dockerfile change, if one is required.
7. Build and inspect the UBI image.
8. Run unit and focused runtime tests.
9. Add required Makefile wrappers.
10. Validate and package the existing Helm chart.
11. Deploy locally and prove ConfigMap-triggered rollout.
12. Repeat on Rancher/RKE2.
13. Record evidence and blockers.
14. Commit, push, and open a draft pull request.

## 20. Simple status update template

Completed:

- Reviewed the upstream Reloader build, UBI image, Makefile, workflows, Helm
  chart, and tests.
- Identified that Reloader already publishes a UBI-derived image.
- Confirmed the minimal-change approach and current acceptance question.

Next:

- Confirm whether the final `scratch` stage satisfies the UBI9 runtime policy.
- Build and test the existing UBI image for AMD64.
- Implement only the approved differences.
- Deploy with the existing Helm chart and validate ConfigMap-triggered rollout.

Blockers:

- Approved UBI9 base/tag or digest.
- SPS target contract and IBM registry access.
- Confirmation of the accepted final-image definition.

## 21. Source references

- Upstream repository: <https://github.com/stakater/Reloader>
- Fork: <https://github.com/zoislam-p/Reloader>
- Reloader documentation: <https://docs.stakater.com/reloader/>
- Helm chart:
  <https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader>
