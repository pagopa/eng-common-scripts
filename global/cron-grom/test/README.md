# CRON GROM Test Cases

This directory contains test configurations for validating CRON GROM's behavior with problematic CronJob scenarios.

## Test Cases Overview

### 1. Resource Constraints Test (`pending-cronjob`)

- Tests CronJob with excessive resource requests
- **Resource Requests:**
    - Memory: 1000Gi
    - CPU: 500 cores
- **Expected Behavior:** Should be suspended due to impossible resource requirements

### 2. Invalid Node Selector Test (`pending-cronjob-bad-nodeselector`)

- Tests CronJob with non-existent node selector
- **Node Selector:** `no-such-node: "ever"`
- **Expected Behavior:** Should be suspended due to impossible node selection

### 3. Heavy Parallel Jobs Test (`heavy-cronjob`)

- Tests CronJob with multiple parallel executions
- **Configuration:**
    - Parallelism: 4
    - Completions: 4
    - Resources per container:
        - Memory: 150Mi
        - CPU: 300m
- **Expected Behavior:** May be suspended if cluster resources are insufficient for parallel execution

## Running Tests

1. Apply the test configurations
2. Wait 5 minutes to bring up some job issues
3. Run the script on your namespace
