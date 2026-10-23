#!/usr/bin/env bash
# Submits a .zip, .dmg or .pkg to Apple's notary service, waits for the verdict and prints the
# notary log when Apple rejects it.
#
# Usage: NOTARY_API_KEY_ID=… NOTARY_API_ISSUER_ID=… NOTARY_API_KEY_PATH=AuthKey.p8 scripts/notarize.sh <file>
set -euo pipefail

file="${1:?usage: notarize.sh <file>}"
key="${NOTARY_API_KEY_PATH:-${RUNNER_TEMP:?set NOTARY_API_KEY_PATH}/AuthKey.p8}"
auth=(--key "$key" --key-id "${NOTARY_API_KEY_ID:?}" --issuer "${NOTARY_API_ISSUER_ID:?}")

# notarytool exits non-zero for rejected submissions too; read the status from its output instead.
result="$(xcrun notarytool submit "$file" "${auth[@]}" --wait --timeout 1h --output-format json || true)"
id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"

if [[ -z "$id" ]]; then
  echo "error: the notary service did not accept the submission: $result" >&2
  exit 1
fi
echo "Notarization $id finished with status: $status"
if [[ "$status" != "Accepted" ]]; then
  xcrun notarytool log "$id" "${auth[@]}" || true
  exit 1
fi
