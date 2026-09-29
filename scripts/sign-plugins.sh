#!/usr/bin/env bash
# Sign every plugin bundle in out/plugins/ with the Antimatter plugin signing key, writing a
# detached binary signature next to it (<bundle>.tar.gz.sig), then verify each signature against
# the committed public key.
#
# The private key is read from, in order:
#   ANTIMATTER_PLUGIN_SIGNING_KEY       armored private key (e.g. a GitHub Actions secret)
#   ANTIMATTER_PLUGIN_SIGNING_KEY_FILE  path to the armored private key
#   ~/.config/antimatter/plugin-signing/private-key.asc

source "$(dirname "$0")/lib.sh"
require gpg

public_key="${ROOT}/keys/antimatter-plugin-signing.asc"
expected_fpr="$(tr -d ' \n' < "${ROOT}/keys/antimatter-plugin-signing.fingerprint")"

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
chmod 700 "${GNUPGHOME}"
cleanup() { gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "${GNUPGHOME}"; }
trap cleanup EXIT

if [[ -n "${ANTIMATTER_PLUGIN_SIGNING_KEY:-}" ]]; then
  printf '%s\n' "${ANTIMATTER_PLUGIN_SIGNING_KEY}" | gpg --batch --quiet --import
else
  key_file="${ANTIMATTER_PLUGIN_SIGNING_KEY_FILE:-${HOME}/.config/antimatter/plugin-signing/private-key.asc}"
  [[ -f "${key_file}" ]] || die "no signing key: set ANTIMATTER_PLUGIN_SIGNING_KEY or ANTIMATTER_PLUGIN_SIGNING_KEY_FILE"
  gpg --batch --quiet --import "${key_file}"
fi

fpr="$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr/ {print $10; exit}')"
[[ "${fpr}" == "${expected_fpr}" ]] || die "signing key ${fpr} does not match keys/antimatter-plugin-signing.fingerprint (${expected_fpr})"

# Verify with a keyring holding only the committed public key.
verify_home="$(mktemp -d)"
chmod 700 "${verify_home}"
GNUPGHOME="${verify_home}" gpg --batch --quiet --import "${public_key}"

shopt -s nullglob
bundles=("${OUT_DIR}"/plugins/*.tar.gz)
shopt -u nullglob
[[ ${#bundles[@]} -gt 0 ]] || die "no plugin bundles in ${OUT_DIR}/plugins"

for bundle in "${bundles[@]}"; do
  log "signing $(basename "${bundle}")"
  gpg --batch --yes --local-user "${fpr}" --detach-sign --output "${bundle}.sig" "${bundle}"
  GNUPGHOME="${verify_home}" gpg --batch --quiet --verify "${bundle}.sig" "${bundle}" 2>/dev/null \
    || die "signature verification failed for ${bundle}"
done
GNUPGHOME="${verify_home}" gpgconf --kill all >/dev/null 2>&1 || true
rm -rf "${verify_home}"
log "signed ${#bundles[@]} plugin bundle(s) with ${fpr}"
