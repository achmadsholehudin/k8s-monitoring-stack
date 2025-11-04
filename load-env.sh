# load-env.sh
#!/usr/bin/env bash
set -Eeuo pipefail

echo "[INFO] Loading environment variables..."
export NAMESPACE=$(yq -r '.namespace.name' custom-values.yaml)
export DOMAIN=$(yq -r '.site.domain' custom-values.yaml)
export INGRESS_CLASS=$(yq -r '.ingress.className' custom-values.yaml)
export CLUSTER_ISSUER=$(yq -r '.certManager.clusterIssuer' custom-values.yaml)
export CERTMANAGER_EMAIL=$(yq -r '.certManager.email' custom-values.yaml)
export STORAGE_CLASS=$(yq -r '.storage.className' custom-values.yaml)
export PROMETHEUS_SIZE=$(yq -r '.storage.prometheus.size' custom-values.yaml)
export GRAFANA_SIZE=$(yq -r '.storage.grafana.size' custom-values.yaml)
export GRAFANA_USER=$(yq -r '.grafana.adminUser' custom-values.yaml)
export GRAFANA_PASS=$(yq -r '.grafana.adminPassword' custom-values.yaml)

for var in NAMESPACE DOMAIN INGRESS_CLASS CLUSTER_ISSUER CERTMANAGER_EMAIL PROMETHEUS_SIZE GRAFANA_SIZE GRAFANA_USER GRAFANA_PASS; do
  if [[ -z "${!var:-}" || "${!var}" == "null" ]]; then
    echo "[ERR] Variable $var is empty. Please check custom-values.yaml." >&2
    exit 1
  fi
done

echo "[OK] Environment variables loaded successfully"
echo "  NAMESPACE=$NAMESPACE"
echo "  DOMAIN=$DOMAIN"
echo "  INGRESS_CLASS=$INGRESS_CLASS"
echo "  CLUSTER_ISSUER=$CLUSTER_ISSUER"
echo "  CERTMANAGER_EMAIL=$CERTMANAGER_EMAIL"
echo "  STORAGE_CLASS=$STORAGE_CLASS"
echo "  PROMETHEUS_SIZE=$PROMETHEUS_SIZE"
echo "  GRAFANA_SIZE=$GRAFANA_SIZE"
