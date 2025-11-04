#!/usr/bin/env bash
set -Eeuo pipefail

# ==== Dependency checks ====
need() { command -v "$1" >/dev/null 2>&1 || { echo "[ERR] Missing dependency: $1" >&2; exit 1; }; }
need kubectl
need yq
need envsubst

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ==== Load environment variables from custom-values.yaml ====
# shellcheck disable=SC1091
source ./load-env.sh

# ==== Helper functions ====

# envsubst with a whitelist of variables to prevent accidental substitution of $1/$2 inside prometheus.yml
render_apply_vars() {
  local vars="$1"; shift
  local file="$1"
  envsubst "$vars" < "$file" | kubectl apply -f -
}

# Apply PVC; remove storageClassName if STORAGE_CLASS is empty (use cluster default)
render_apply_pvc() {
  local file="$1"
  local rendered
  rendered=$(envsubst '${NAMESPACE}${STORAGE_CLASS}${PROMETHEUS_SIZE}${GRAFANA_SIZE}' < "$file")
  if [[ -z "${STORAGE_CLASS:-}" || "${STORAGE_CLASS}" == '""' ]]; then
    echo "$rendered" | yq 'del(.spec.storageClassName)' | kubectl apply -f -
  else
    echo "$rendered" | kubectl apply -f -
  fi
}

# ==== Detect Prometheus mode (Deployment vs StatefulSet) ====
PROM_STS_FILE="manifests/prometheus/statefulset.yaml"
PROM_HEADLESS_SVC_FILE="manifests/prometheus/service-headless.yaml"
if [[ -f "$PROM_STS_FILE" ]]; then
  PROM_MODE="statefulset"
  echo "[INFO] Prometheus mode: StatefulSet (per-replica PVC via volumeClaimTemplates)"
else
  PROM_MODE="deployment"
  echo "[INFO] Prometheus mode: Deployment (single PVC)"
fi

# ==== Namespace & RBAC ====
render_apply_vars '${NAMESPACE}' manifests/namespace/namespace.yaml
render_apply_vars '${NAMESPACE}' manifests/rbac/prometheus-rbac.yaml

# ==== Persistent Volume Claims ====
# Prometheus PVC: only for Deployment mode (StatefulSet will create per-pod PVCs)
if [[ "$PROM_MODE" == "deployment" ]]; then
  render_apply_pvc manifests/pvc/prometheus-pvc.yaml
else
  echo "[INFO] Skipping manifests/pvc/prometheus-pvc.yaml (StatefulSet will provision PVCs)"
fi
render_apply_pvc manifests/pvc/grafana-pvc.yaml

# ==== Grafana admin credentials ====
kubectl -n "$NAMESPACE" delete secret grafana-admin-credentials --ignore-not-found
kubectl -n "$NAMESPACE" create secret generic grafana-admin-credentials \
  --from-literal=admin-user="$GRAFANA_USER" \
  --from-literal=admin-password="$GRAFANA_PASS"

# ==== PostgreSQL (DIY) ====
if [[ "${PG_ENABLED}" == "true" ]]; then
  echo "[INFO] Deploying PostgreSQL (DIY) for Grafana..."
  # DB credentials secret
  kubectl -n "$NAMESPACE" delete secret grafana-db --ignore-not-found
  kubectl -n "$NAMESPACE" create secret generic grafana-db \
    --from-literal=username="$PG_USER" \
    --from-literal=password="$PG_PASS" \
    --from-literal=db-name="$PG_DB"

  # Grafana secret key (stable across pods)
  if ! kubectl -n "$NAMESPACE" get secret grafana-secret >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" create secret generic grafana-secret \
      --from-literal=secret-key="$(head -c 32 /dev/urandom | base64)"
  fi

  # Service
  render_apply_vars '${NAMESPACE}${PG_SVC_NAME}${PG_PORT}' manifests/postgres/service.yaml

  # StatefulSet — handle empty STORAGE_CLASS
  rendered_pg=$(envsubst '${NAMESPACE}${IMAGE_POSTGRES}${PG_SVC_NAME}${PG_DB}${STORAGE_CLASS}${POSTGRES_SIZE}' < manifests/postgres/statefulset.yaml)
  if [[ -z "${STORAGE_CLASS:-}" || "${STORAGE_CLASS}" == '""' ]]; then
    echo "$rendered_pg" | yq '(.spec.volumeClaimTemplates[]?.spec) |= del(.storageClassName)' | kubectl apply -f -
  else
    echo "$rendered_pg" | kubectl apply -f -
  fi
else
  echo "[INFO] PostgreSQL disabled (postgres.enabled=false). Skipping DB deployment."
fi

# ==== Prometheus ====
render_apply_vars '${NAMESPACE}' manifests/prometheus/configmap.yaml
if [[ "$PROM_MODE" == "deployment" ]]; then
  render_apply_vars '${NAMESPACE}${IMAGE_PROMETHEUS}${REPLICA_PROMETHEUS}' manifests/prometheus/deployment.yaml
  render_apply_vars '${NAMESPACE}' manifests/prometheus/service.yaml
else
  render_apply_vars '${NAMESPACE}' manifests/prometheus/service.yaml || true
  if [[ -f "$PROM_HEADLESS_SVC_FILE" ]]; then
    render_apply_vars '${NAMESPACE}' "$PROM_HEADLESS_SVC_FILE"
  fi
  render_apply_vars '${NAMESPACE}${IMAGE_PROMETHEUS}${REPLICA_PROMETHEUS}${STORAGE_CLASS}${PROMETHEUS_SIZE}' "$PROM_STS_FILE"
fi

# ==== Grafana ====
# (Pastikan deployment Grafana kamu sudah membaca GF_DATABASE_* env kalau PG_ENABLED=true)
render_apply_vars '${NAMESPACE}${IMAGE_GRAFANA}${REPLICA_GRAFANA}${PG_SVC_NAME}${PG_PORT}' manifests/grafana/deployment.yaml
render_apply_vars '${NAMESPACE}' manifests/grafana/service.yaml

# ==== Horizontal Pod Autoscaler ====
if [[ "${AUTOSCALING_ENABLED}" == "true" ]]; then
  if [[ "$PROM_MODE" == "deployment" ]]; then
    render_apply_vars '${NAMESPACE}${HPA_PROM_MIN}${HPA_PROM_MAX}${HPA_PROM_CPU}${HPA_PROM_MEM}' manifests/hpa/prometheus-hpa.yaml || true
  else
    echo "[INFO] Skipping Prometheus HPA for StatefulSet mode (not recommended)."
  fi
  render_apply_vars '${NAMESPACE}${HPA_GRAF_MIN}${HPA_GRAF_MAX}${HPA_GRAF_CPU}${HPA_GRAF_MEM}' manifests/hpa/grafana-hpa.yaml || true
else
  echo "[INFO] Autoscaling disabled. Skipping HPA manifests."
fi

# ==== Cert-manager ClusterIssuer (staging/prod) ====
case "$CLUSTER_ISSUER" in
  letsencrypt-staging) render_apply_vars '${CERTMANAGER_EMAIL}${INGRESS_CLASS}' manifests/tls/tls-staging.yaml ;;
  letsencrypt-prod)    render_apply_vars '${CERTMANAGER_EMAIL}${INGRESS_CLASS}' manifests/tls/tls-prod.yaml ;;
  *) echo "[WARN] Unknown CLUSTER_ISSUER=$CLUSTER_ISSUER. Falling back to tls-prod.yaml." >&2
     render_apply_vars '${CERTMANAGER_EMAIL}${INGRESS_CLASS}' manifests/tls/tls-prod.yaml ;;
esac

# ==== Certificate ====
render_apply_vars '${NAMESPACE}${DOMAIN}${CLUSTER_ISSUER}' manifests/tls/certificate.yaml

# ==== Ingress (Grafana) ====
render_apply_vars '${NAMESPACE}${DOMAIN}${INGRESS_CLASS}${CLUSTER_ISSUER}' manifests/ingress/ingress.yaml

# ==== Rollout status ====
if [[ "$PROM_MODE" == "deployment" ]]; then
  kubectl -n "$NAMESPACE" rollout status deploy/prometheus --timeout=180s || true
else
  kubectl -n "$NAMESPACE" rollout status statefulset/prometheus --timeout=240s || true
fi
kubectl -n "$NAMESPACE" rollout status deploy/grafana --timeout=180s || true
if [[ "${PG_ENABLED}" == "true" ]]; then
  kubectl -n "$NAMESPACE" rollout status statefulset/grafana-postgresql --timeout=240s || true
fi

# ==== Status summary ====
echo
kubectl -n "$NAMESPACE" get certificate 2>/dev/null || true
kubectl -n "$NAMESPACE" get secret grafana-tls 2>/dev/null || true
kubectl -n "$NAMESPACE" get ingress grafana-ingress -o wide 2>/dev/null || true
if [[ "$PROM_MODE" == "statefulset" ]]; then
  kubectl -n "$NAMESPACE" get sts,pvc | grep -E '^statefulset|^pvc' || true
fi
if [[ "${PG_ENABLED}" == "true" ]]; then
  kubectl -n "$NAMESPACE" get svc,sts,pvc | grep -E 'grafana-postgresql|data-grafana-postgresql' || true
fi

echo
echo "[DONE] Deployment completed successfully for namespace: $NAMESPACE"
echo "Grafana is available at: https://$DOMAIN/"
