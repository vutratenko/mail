#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-mail}"
DEPLOYMENT="${DEPLOYMENT:-docker-mailserver}"
EMAIL="${EMAIL:-vladimir@sion2k.ru}"
ALIAS_FROM="${ALIAS_FROM:-postmaster@sion2k.ru}"
DOMAIN="${DOMAIN:-sion2k.ru}"

usage() {
  cat <<EOF
Usage: $0 <mailbox-password>

Creates mailbox ${EMAIL}, alias ${ALIAS_FROM} -> ${EMAIL}, and DKIM for ${DOMAIN}.
Password is not stored in git; pass it as the only argument or via MAILBOX_PASSWORD.

Environment overrides:
  NAMESPACE, DEPLOYMENT, EMAIL, ALIAS_FROM, DOMAIN
EOF
}

PASSWORD="${1:-${MAILBOX_PASSWORD:-}}"
if [[ -z "${PASSWORD}" ]]; then
  usage
  exit 1
fi

echo "Waiting for deployment/${DEPLOYMENT} in namespace ${NAMESPACE}..."
kubectl -n "${NAMESPACE}" rollout status "deploy/${DEPLOYMENT}" --timeout=600s

echo "Creating mailbox ${EMAIL}..."
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- setup email add "${EMAIL}" "${PASSWORD}"

echo "Creating alias ${ALIAS_FROM} -> ${EMAIL}..."
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- setup alias add "${ALIAS_FROM}" "${EMAIL}"

echo "Generating DKIM for ${DOMAIN}..."
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- setup config dkim domain "${DOMAIN}"

echo
echo "DKIM DNS record (add to nic.ru):"
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- cat "/tmp/docker-mailserver/opendkim/keys/${DOMAIN}/mail.txt" 2>/dev/null \
  || kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- find /tmp/docker-mailserver -name 'mail.txt' -exec cat {} \;

echo
echo "Done. Update DNS: MX, SPF, DKIM, DMARC, PTR (see README.md)."
