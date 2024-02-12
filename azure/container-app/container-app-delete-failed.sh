#!/bin/bash

#
# 🚀 GOAL
# This script allows to find all the container apps that are in Failed state within a subscription
# and then delete them
#

# Set the errexit, nounset and pipefail options to write more robust and secure bash code
set -euo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 subscription"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "jq is required but not installed. Please install it from [here]."
  exit 1
fi

if ! command -v az &> /dev/null; then
  echo "az is required but not installed. Please install it from [here]."
  exit 1
fi

pids=()
subscription="$1"

az account set --subscription "$subscription"

containerapps=$(az containerapp list --query "[].{name:name, resourceGroup:resourceGroup}")

for containerapp in $(echo "$containerapps" | jq -c '.[]'); do
  name=$(echo "$containerapp" | jq -r ".name")
  resource_group=$(echo "$containerapp" | jq -r ".resourceGroup")
  # Use the -e and -n options to interpret the special characters and not add a new line at the end
  echo -e -n "Checking the revisions of the container app $name in the resource group: $resource_group...\n"
  # Get the list of revisions of the container app
  is_failed=$(az containerapp revision list --all --name "$name" --resource-group "$resource_group" --query "[0].properties.runningState == 'Failed'")
  # Check that the az containerapp revision list command was successful and otherwise print an error message and exit the script
  if [ $? -ne 0 ]; then
    echo "Error: failed to get the revision list for container app $name in resource group $resource_group"
    exit 1
  fi
  echo "$is_failed"
  # Use double quotes to expand the is_failed variable and check if it is equal to true
  if [ "$is_failed" = "true" ]; then
      echo "Delete container app with name: $name on resourceGroup: $resource_group"
      az containerapp delete --name "$name" --resource-group "$resource_group" --subscription "$subscription" --yes &
      # Check that the az containerapp delete command was successful and otherwise print an error message and continue the loop
      if [ $? -ne 0 ]; then
        echo "Error: failed to delete container app $name in resource group $resource_group"
        continue
      fi
      pids+=($!)
  fi
done

if [ -z "${pids:-}" ]; then
  echo "All container app are in state OK"
  exit 0
fi

for pid in "${pids[@]}"; do
  wait "$pid"
  # Check that the wait command was successful and otherwise print an error message and exit the script
  if [ $? -ne 0 ]; then
    echo "Error: failed to wait for process $pid"
    exit 1
  fi
done
