#!/usr/bin/env bash

set -euo pipefail

CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"
IMAGE="${IMAGE:-reloader-local:ubi9}"
EXPECTED_PLATFORM="${EXPECTED_PLATFORM:-linux/amd64}"
EXPECTED_USER="${EXPECTED_USER:-65532:65532}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

command -v "${CONTAINER_ENGINE}" >/dev/null ||
  fail "container engine not found: ${CONTAINER_ENGINE}"

actual_platform="$("${CONTAINER_ENGINE}" image inspect "${IMAGE}" \
  --format '{{.Os}}/{{.Architecture}}')"
actual_user="$("${CONTAINER_ENGINE}" image inspect "${IMAGE}" \
  --format '{{.Config.User}}')"
entrypoint="$("${CONTAINER_ENGINE}" image inspect "${IMAGE}" \
  --format '{{json .Config.Entrypoint}}')"

[[ "${actual_platform}" == "${EXPECTED_PLATFORM}" ]] ||
  fail "expected ${EXPECTED_PLATFORM}, found ${actual_platform}"
[[ "${actual_user}" == "${EXPECTED_USER}" ]] ||
  fail "expected image user ${EXPECTED_USER}, found ${actual_user}"
[[ "${entrypoint}" == '["/manager"]' ]] ||
  fail "expected /manager entrypoint, found ${entrypoint}"

container_id="$("${CONTAINER_ENGINE}" create --platform "${EXPECTED_PLATFORM}" "${IMAGE}")"
tmp_dir="$(mktemp -d)"
cleanup() {
  "${CONTAINER_ENGINE}" rm -f "${container_id}" >/dev/null 2>&1 || true
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

"${CONTAINER_ENGINE}" cp "${container_id}:/etc/redhat-release" \
  "${tmp_dir}/redhat-release"
"${CONTAINER_ENGINE}" cp "${container_id}:/manager" "${tmp_dir}/manager"

grep -Eq 'Red Hat Enterprise Linux release 9([.]| )' \
  "${tmp_dir}/redhat-release" ||
  fail "RHEL/UBI 9 release evidence was not found"

file "${tmp_dir}/manager" | grep -q 'x86-64' ||
  fail "/manager is not an x86-64 binary"

echo "PASS: ${IMAGE}"
echo "  platform=${actual_platform}"
echo "  imageUser=${actual_user}"
echo "  entrypoint=${entrypoint}"
echo "  release=$(tr -d '\n' <"${tmp_dir}/redhat-release")"
echo "  binary=$(file "${tmp_dir}/manager")"
