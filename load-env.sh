#!/usr/bin/env bash
set -Eeuo pipefail

echo "[INFO] Loading environment variables..."

# Core
export NAMESPACE=$(yq -r '.namespace.name' custom-values.yaml)
export DOMAIN=$(yq -r '.site.domain' custom-values.yaml)
export INGRESS_CLASS=$(yq -r '.ingress.className' custom-values.yaml)
export CLUSTER_ISSUER=$(yq -r '.certManager.clusterIssuer' custom-values.yaml)
export CERTMANAGER_EMAIL=$(yq -r '.certManager.email' custom-values.yaml)

# Storage
export STORAGE_CLASS=$(yq -r '.storage.className' custom-values.yaml)
export PROMETHEUS_SIZE=$(yq -r '.storage.prometheus.size' custom-values.yaml)
export GRAFANA_SIZE=$(yq -r '.storage.grafana.size' custom-values.yaml)
export POSTGRES_SIZE=$(yq -r '.storage.postgres.size' custom-values.yaml)

# Grafana admin
export GRAFANA_USER=$(yq -r '.grafana.adminUser' custom-values.yaml)
export GRAFANA_PASS=$(yq -r '.grafana.adminPassword' custom-values.yaml)

# Images & replicas
export IMAGE_PROMETHEUS=$(yq -r '.images.prometheus' custom-values.yaml)
export IMAGE_GRAFANA=$(yq -r '.images.grafana' custom-values.yaml)
export IMAGE_POSTGRES=$(yq -r '.images.postgres' custom-values.yaml)

export REPLICA_PROMETHEUS=$(yq -r '.replicas.prometheus' custom-values.yaml)
export REPLICA_GRAFANA=$(yq -r '.replicas.grafana' custom-values.yaml)
export REPLICA_POSTGRES=$(yq -r '.replicas.postgres' custom-values.yaml)

# Autoscaling
export AUTOSCALING_ENABLED=$(yq -r '.autoscaling.enabled' custom-values.yaml)
export HPA_PROM_MIN=$(yq -r '.autoscaling.prometheus.minReplicas' custom-values.yaml)
export HPA_PROM_MAX=$(yq -r '.autoscaling.prometheus.maxReplicas' custom-values.yaml)
export HPA_PROM_CPU=$(yq -r '.autoscaling.prometheus.targetCPUUtilizationPercentage' custom-values.yaml)
export HPA_PROM_MEM=$(yq -r '.autoscaling.prometheus.targetMemoryUtilizationPercentage' custom-values.yaml)
export HPA_GRAF_MIN=$(yq -r '.autoscaling.grafana.minReplicas' custom-values.yaml)
export HPA_GRAF_MAX=$(yq -r '.autoscaling.grafana.maxReplicas' custom-values.yaml)
export HPA_GRAF_CPU=$(yq -r '.autoscaling.grafana.targetCPUUtilizationPercentage' custom-values.yaml)
export HPA_GRAF_MEM=$(yq -r '.autoscaling.grafana.targetMemoryUtilizationPercentage' custom-values.yaml)

# PostgreSQL (DIY)
export PG_ENABLED=$(yq -r '.postgres.enabled' custom-values.yaml)
export PG_SVC_NAME=$(yq -r '.postgres.service.name' custom-values.yaml)
export PG_PORT=$(yq -r '.postgres.service.port' custom-values.yaml)
export PG_DB=$(yq -r '.postgres.auth.dbName' custom-values.yaml)
export PG_USER=$(yq -r '.postgres.auth.user' custom-values.yaml)
export PG_PASS=$(yq -r '.postgres.auth.password' custom-values.yaml)

# ---- Defaults for optional fields ----
[[ -z "${IMAGE_PROMETHEUS:-}" || "${IMAGE_PROMETHEUS}" == "null" ]] && IMAGE_PROMETHEUS="prom/prometheus:v2.55.0"
[[ -z "${IMAGE_GRAFANA:-}"   || "${IMAGE_GRAFANA}"   == "null" ]] && IMAGE_GRAFANA="grafana/grafana:11.2.0"
[[ -z "${IMAGE_POSTGRES:-}"  || "${IMAGE_POSTGRES}"  == "null" ]] && IMAGE_POSTGRES="postgres:16-alpine"

[[ -z "${REPLICA_PROMETHEUS:-}" || "${REPLICA_PROMETHEUS}" == "null" ]] && REPLICA_PROMETHEUS=1
[[ -z "${REPLICA_GRAFANA:-}"    || "${REPLICA_GRAFANA}"    == "null" ]] && REPLICA_GRAFANA=1
[[ -z "${REPLICA_POSTGRES:-}"   || "${REPLICA_POSTGRES}"   == "null" ]] && REPLICA_POSTGRES=1

[[ -z "${AUTOSCALING_ENABLED:-}" || "${AUTOSCALING_ENABLED}" == "null" ]] && AUTOSCALING_ENABLED="false"

[[ -z "${PG_ENABLED:-}" || "${PG_ENABLED}" == "null" ]] && PG_ENABLED="false"
[[ -z "${PG_PORT:-}"    || "${PG_PORT}"    == "null" ]] && PG_PORT="5432"
[[ -z "${PG_DB:-}"      || "${PG_DB}"      == "null" ]] && PG_DB="grafana"
[[ -z "${PG_USER:-}"    || "${PG_USER}"    == "null" ]] && PG_USER="grafana"
[[ -z "${PG_PASS:-}"    || "${PG_PASS}"    == "null" ]] && PG_PASS="change-me"
[[ -z "${POSTGRES_SIZE:-}" || "${POSTGRES_SIZE}" == "null" ]] && POSTGRES_SIZE="5Gi"

# ---- Required fields sanity check ----
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
echo "  POSTGRES_SIZE=$POSTGRES_SIZE"
echo "  IMAGE_PROMETHEUS=$IMAGE_PROMETHEUS"
echo "  IMAGE_GRAFANA=$IMAGE_GRAFANA"
echo "  IMAGE_POSTGRES=$IMAGE_POSTGRES"
echo "  REPLICA_PROMETHEUS=$REPLICA_PROMETHEUS"
echo "  REPLICA_GRAFANA=$REPLICA_GRAFANA"
echo "  REPLICA_POSTGRES=$REPLICA_POSTGRES"
echo "  AUTOSCALING_ENABLED=$AUTOSCALING_ENABLED"
echo "  PG_ENABLED=$PG_ENABLED"
echo "  PG_SVC_NAME=$PG_SVC_NAME"
echo "  PG_PORT=$PG_PORT"
echo "  PG_DB=$PG_DB"
