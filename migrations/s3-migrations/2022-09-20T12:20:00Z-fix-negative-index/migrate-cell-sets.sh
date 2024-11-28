#!/bin/bash

set -euo pipefail


experiment_id=$1
original_pwd=$(pwd)
migration_log_file=${original_pwd}/migration-${MIGRATION_ENV}.log

## 1. Download experiment
echo "[INFO] Downloading ${experiment_id}" | tee -a ${migration_log_file}

biomage experiment download \
    --without_tunnel \
    -e ${experiment_id} \
    -i ${MIGRATION_ENV} \
    -o ${DATA_MIGRATION_PATH}/${experiment_id} \
    -f raw_rds \
    -f processed_rds \
    -f cellsets \
    -f filtered_cells

## 2. Check how many experiments contain -1s

cd ${DATA_MIGRATION_PATH}/${experiment_id}

echo "[INFO] Checking ${experiment_id}" | tee -a ${migration_log_file}

# verify that cell sets contain a -1
if [ "$(grep -v ',-1' cellsets.json)" != "" ]; then
    echo "[SKIP]: ${experiment_id} cellsets does not contain -1" | tee -a ${migration_log_file}
    exit 0
fi

# needed to iterate over folders/filenames with spaces
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

# check that one raw sample file contains -1
exists_wrong_sample=false
for sample in $(ls raw/*/*rds); do
    if [ "$(R -e 'any(readRDS("'${sample}'")$cells_id == -1)' | grep TRUE)" != "" ]; then
        exists_wrong_sample=true
    fi
done

if [ "${exists_wrong_sample}" != "true" ]; then
    echo "[SKIP]: ${experiment_id} raw samples do not contain -1" | tee -a ${migration_log_file}
    exit 0
fi

# 3. Migrate files to stop using -1

echo "[INFO] Patching" | tee -a ${migration_log_file}
# Migrate processed RDS
mv processed_r.rds processed_r.rds.orig
R -e 'data <- readRDS("processed_r.rds.orig")
      data$cells_id <- data$cells_id+1
      saveRDS(data, "processed_r.rds")'

echo "[INFO] processed_r.rds patched" | tee -a ${migration_log_file}


# Migrate raw samples RDS
for sample in $(ls raw/*/*.rds); do
    mv "${sample}" "${sample}.orig"
    R -e 'data <- readRDS("'${sample}'.orig")
      data$cells_id <- data$cells_id+1
      saveRDS(data, "'${sample}'", compress = FALSE)'
done
echo "[INFO] raw/*/*.rds patched" | tee -a ${migration_log_file}

# Migrate cellsets
python3 ${original_pwd}/cellsets-patch.py

echo "[INFO] cellsets patched" | tee -a ${migration_log_file}

# Migrate filtered cells
for sample in $(ls filtered-cells/*/*.rds); do
    mv "${sample}" "${sample}.orig"
    R -e 'data <- readRDS("'${sample}'.orig")
      data <- lapply(data, `+`, 1)
      saveRDS(data, "'${sample}'")'
done
echo "[INFO] filtered cells patched" | tee -a ${migration_log_file}

# 4. Check that the results do not contain -1s

# verify that cell sets contain do not contain -1
if [ "$(grep ',-1' cellsets.json)" != "" ]; then
    echo "[FAIL]: ${experiment_id} cellsets still contain -1" | tee -a ${migration_log_file}
    exit 1
fi

# verify that processed_r.rds file does not contain -1
if [ "$(R -e 'any(readRDS("processed_r.rds")$cells_id == -1)' | grep FALSE)" = "" ]; then
    echo "[FAIL]: ${experiment_id} processed_r still contain -1" | tee -a ${migration_log_file}
    exit 1
fi


# check that raw samples file do not contain -1
exists_wrong_sample=false
for sample in $(ls raw/*/*.rds); do
    if [ "$(R -e 'any(readRDS("'${sample}'")$cells_id == -1)' | grep TRUE)" != "" ]; then
        exists_wrong_sample=true
    fi
done

if [ "${exists_wrong_sample}" = "true" ]; then
    echo "[FAIL]: ${experiment_id} raw samples still contain -1" | tee -a ${migration_log_file}
    exit 1
fi


## 5. Upload the resulting files into S3
biomage experiment upload \
    --without_tunnel \
    -e ${experiment_id} \
    -o ${MIGRATION_ENV} \
    -i ${DATA_MIGRATION_PATH}/${experiment_id} \
    -f raw_rds \
    -f processed_rds \
    -f cellsets \
    -f filtered_cells

echo "[INFO] Successfully patched ${experiment_id}" | tee -a ${migration_log_file}

## 6. Migrate state machines dates and remove state machine for qc
state_machine_arn=$(echo "select state_machine_arn
from experiment_execution ee
where experiment_id = '${experiment_id}' and "pipeline_type" = 'qc'"  |
      biomage rds run -i ${MIGRATION_ENV} psql |
      grep 'arn:' |
      xargs)

aws stepfunctions delete-state-machine --state-machine-arn ${state_machine_arn}
echo "[INFO] Deleted state machine ${state_machine_arn} for ${experiment_id}"  | tee -a ${migration_log_file}


echo "UPDATE experiment_execution SET
last_status_response = jsonb_set(
    last_status_response,
    '{qc}', last_status_response->'qc' || '{\"startDate\": \"2022-09-26T00:00:00.000Z\", \"stopDate\": \"2022-09-26T00:00:00.000Z\"}')
where experiment_id = '${experiment_id}' and pipeline_type = 'qc'"  |
      biomage rds run -i ${MIGRATION_ENV} psql

echo "[INFO] Migrated QC to new date for ${experiment_id}"  | tee -a ${migration_log_file}

echo "UPDATE experiment_execution SET
last_status_response = jsonb_set(
    last_status_response,
    '{gem2s}', last_status_response->'gem2s' || '{\"startDate\": \"2022-09-26T00:00:00.000Z\", \"stopDate\": \"2022-09-26T00:00:00.000Z\"}')
where experiment_id = '${experiment_id}' and pipeline_type = 'gem2s'"  |
      biomage rds run -i ${MIGRATION_ENV} psql

echo "[OK] Migrated ${experiment_id}"  | tee -a ${migration_log_file}

