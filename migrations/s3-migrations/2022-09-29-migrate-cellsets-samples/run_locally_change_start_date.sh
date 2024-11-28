# Requires tunnel to whatever MIGRATION_ENV this is being run on
MIGRATION_ENV=production

for experiment_id in $(cat affected-experiment-ids.txt); do
  state_machine_arn=$(echo "select state_machine_arn
  from experiment_execution ee
  where experiment_id = '${experiment_id}' and "pipeline_type" = 'qc'"  |
        biomage rds run -i ${MIGRATION_ENV} psql |
        grep 'arn:' |
        xargs)

  aws stepfunctions delete-state-machine --state-machine-arn ${state_machine_arn}
  echo "[INFO] Deleted state machine ${state_machine_arn} for ${experiment_id}"


  echo "UPDATE experiment_execution SET
  last_status_response = jsonb_set(
      last_status_response,
      '{qc}', last_status_response->'qc' || '{\"startDate\": \"2022-09-26T00:00:00.000Z\", \"stopDate\": \"2022-09-26T00:00:00.000Z\"}')
  where experiment_id = '${experiment_id}' and pipeline_type = 'qc'"  |
        biomage rds run -i ${MIGRATION_ENV} psql

  echo "[INFO] Migrated QC to new date for ${experiment_id}"

  echo "UPDATE experiment_execution SET
  last_status_response = jsonb_set(
      last_status_response,
      '{gem2s}', last_status_response->'gem2s' || '{\"startDate\": \"2022-09-26T00:00:00.000Z\", \"stopDate\": \"2022-09-26T00:00:00.000Z\"}')
  where experiment_id = '${experiment_id}' and pipeline_type = 'gem2s'"  |
        biomage rds run -i ${MIGRATION_ENV} psql

  echo "[OK] Migrated ${experiment_id}"
done