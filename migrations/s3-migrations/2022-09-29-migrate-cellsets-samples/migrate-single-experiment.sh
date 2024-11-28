#!/bin/bash
# This script needs to be run from within pipeline_runner becuase it needs Seurat

set -euo pipefail


experiment_id=$1
original_pwd=$(pwd)
migration_log_file=${original_pwd}/migration-${MIGRATION_ENV}.log

## Download experiment
echo "[INFO] Downloading ${experiment_id}" | tee -a ${migration_log_file}

biomage experiment download \
    --without_tunnel \
    -e ${experiment_id} \
    -i ${MIGRATION_ENV} \
    -f raw_rds \
    -f cellsets

## 3. Migrate cellsets

echo "[INFO] Migrating cellsets" | tee -a ${migration_log_file}

# Migrate cellsets
Rscript create_sample_cellsets.R ${experiment_id}

echo "[INFO] cellsets migrated" | tee -a ${migration_log_file}

## Upload the resulting files into S3
biomage experiment upload \
    --without_tunnel \
    -e ${experiment_id} \
    -o ${MIGRATION_ENV} \
    -f cellsets

echo "[INFO] Successfully patched ${experiment_id}" | tee -a ${migration_log_file}

echo "[OK] Migrated ${experiment_id}"  | tee -a ${migration_log_file}

