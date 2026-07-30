#!/usr/bin/env bash

set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-reloader-ubi9}"
RELOADER_NAMESPACE="${RELOADER_NAMESPACE:-reloader}"
TEST_NAMESPACE="${TEST_NAMESPACE:-reloader-test}"
TEST_MANIFEST="${TEST_MANIFEST:-deployments/local-test/reload-test.yaml}"
TIMEOUT="${TIMEOUT:-180s}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

command -v kubectl >/dev/null || fail "kubectl is required"

kubectl --context "${KUBE_CONTEXT}" -n "${RELOADER_NAMESPACE}" \
  rollout status deployment/reloader-reloader --timeout="${TIMEOUT}"

kubectl --context "${KUBE_CONTEXT}" apply -f "${TEST_MANIFEST}"
kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  rollout status deployment/reloader-test-app --timeout="${TIMEOUT}"

initial_pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  get pod -l app=reloader-test-app \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')"
initial_revision="$(kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  get deployment reloader-test-app \
  -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"

test_value="reload-$(date +%s)"
kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  patch configmap reloader-test-config --type merge \
  -p "{\"data\":{\"MESSAGE\":\"${test_value}\"}}"

kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  rollout status deployment/reloader-test-app --timeout="${TIMEOUT}"

new_pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  get pod -l app=reloader-test-app \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')"
new_revision="$(kubectl --context "${KUBE_CONTEXT}" -n "${TEST_NAMESPACE}" \
  get deployment reloader-test-app \
  -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"

[[ "${initial_pod}" != "${new_pod}" ]] ||
  fail "ConfigMap update did not replace the application pod"
(( new_revision > initial_revision )) ||
  fail "Deployment revision did not increase"

log_match="$(kubectl --context "${KUBE_CONTEXT}" -n "${RELOADER_NAMESPACE}" \
  logs deployment/reloader-reloader --since=5m |
  grep "Changes detected in 'reloader-test-config'" |
  tail -1 || true)"
[[ -n "${log_match}" ]] ||
  fail "Reloader change-detection log was not found"

echo "PASS: Reloader ConfigMap rollout"
echo "  initialPod=${initial_pod}"
echo "  newPod=${new_pod}"
echo "  initialRevision=${initial_revision}"
echo "  newRevision=${new_revision}"
echo "  log=${log_match}"
