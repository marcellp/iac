#!/bin/bash

# The script relies on the following environment variables
export MIGRATION_ENV=production
export BIOMAGE_DATA_PATH=/src/pipeline-runner/2022-09-29-migrate-cellsets-samples/data

for experiment_id in $(cat affected-experiment-ids.txt); do
  ./migrate-single-experiment.sh ${experiment_id}
  rm -rf data/${experiment_id}
done
