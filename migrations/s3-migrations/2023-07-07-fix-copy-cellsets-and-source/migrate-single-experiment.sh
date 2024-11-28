#!/bin/bash
# This script needs to be run from within pipeline_runner becuase it needs Seurat

set -euo pipefail


experiment_id=$1
download=$2
upload=$3

original_pwd=$(pwd)
migration_log_file=${original_pwd}/migration-${MIGRATION_ENV}.log

mkdir -p "out/$experiment_id"

if $download == "true"
then
    # Download experiment
    echo "[INFO] Downloading ${experiment_id}" | tee -a ${migration_log_file}

    biomage experiment download \
        --without_tunnel \
        -e ${experiment_id} \
        -i ${MIGRATION_ENV} \
        -o ${BIOMAGE_DATA_PATH} \
        -f raw_rds \
        -f cellsets

    # Download experiment
    echo "[INFO] Finished downloading ${experiment_id}" | tee -a ${migration_log_file}
else
    echo "[INFO] Not downloading ${experiment_id} because download is false" | tee -a ${migration_log_file}
fi

## 3. Migrate cellsets

echo "[INFO] Migrating cellsets" | tee -a ${migration_log_file}

python fix_cell_sets.py ${experiment_id}

echo "[INFO] cellsets migrated" | tee -a ${migration_log_file}

## 4. Migrate source

echo "[INFO] Migrating source" | tee -a ${migration_log_file}

Rscript fix_source_objects.R ${experiment_id}

echo "[INFO] source migrated" | tee -a ${migration_log_file}

echo "[INFO] Finished patching files for experiment ${experiment_id}" | tee -a ${migration_log_file}

# Upload the resulting files into S3
if $upload == "true"
then
    biomage experiment upload \
        --without_tunnel \
        -e ${experiment_id} \
        -i ${BIOMAGE_DATA_PATH_OUT}/${experiment_id} \
        -o ${MIGRATION_ENV} \
        -f cellsets

    biomage experiment upload \
        --without_tunnel \
        -e ${experiment_id} \
        -i ${BIOMAGE_DATA_PATH_OUT} \
        -o ${MIGRATION_ENV} \
        -f raw_rds

    echo "[OK] Uploaded new ${experiment_id} files"  | tee -a ${migration_log_file}
else 
    echo "[OK] New files not uploaded because upload is set to false"
fi


