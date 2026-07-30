# Reloader UBI9 Migration Documentation

Use these documents together:

| Document | Audience and purpose |
|---|---|
| `RELOADER-UBI9-MIGRATION-LEARNING-GUIDE.md` | End-to-end project context and learning guide |
| `RELOADER-UBI9-LOCAL-TESTING-GUIDE.md` | Exact local build, image, Helm, and Kubernetes test procedure |
| `RELOADER-UBI9-LOCAL-VALIDATION-REPORT.md` | Dated evidence, results, limitations, and blockers |
| `RELOADER-UBI9-LOCAL-VALIDATION-REPORT.docx` | Shareable manager-facing version of the validation report |

Supporting test assets:

- `deployments/local-test/values-ubi9.yaml`
- `deployments/local-test/reload-test.yaml`
- `hack/verify-ubi9-image.sh`
- `hack/test-local-reload.sh`
- `evidence/reloader-ubi9-local-validation-2026-07-30.txt`

The local report proves development-environment behavior. It does not replace
SPS, vulnerability, SBOM, signing, registry, Rancher/RKE2, or production
acceptance evidence.
