#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl apply -f "${ROOT}/argocd/application.yaml"
echo "Applied Argo CD Application mail in namespace shturval-cd"
