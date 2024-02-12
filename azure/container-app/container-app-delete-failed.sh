#!/bin/bash

set -eu

pids=()
subscription=$1

# Imposta la subscription di Azure
az account set --subscription "$subscription"

# Ottieni la lista delle container app e dei loro resource group
containerapps=$(az containerapp list --query "[].{name:name, resourceGroup:resourceGroup}")

#echo $containerapps
# Per ogni coppia nome-resource group, assegna le variabili app e group
for containerapp in $(echo "$containerapps" | jq -c '.[]'); do
  name=$(echo "$containerapp" | jq -r .name)
  resource_group=$(echo "$containerapp" | jq -r .resourceGroup)
  echo "Controllando le revisioni della container app $name nel resource group: $resource_group..."
  # Ottieni la lista delle revisioni della container app
  is_failed=$(az containerapp revision list --all --name "$name" --resource-group "$resource_group" --query "[0].properties.runningState == 'Failed'")
  echo "$is_failed"
  if [ "$is_failed" ]; then
      echo "Delete container app with name: $name on resourceGroup: $resource_group"
      az containerapp delete --name "$name" --resource-group "$resource_group" --subscription "$subscription" --yes &
      pids+=($!)
  fi
done

if [ -z "${pids:-}" ]; then
  echo "All container app are in state OK"
  exit 0
fi

for pid in "${pids[@]}"; do
  #
  # Waiting on a specific PID makes the wait command return with the exit
  # status of that process. Because of the 'set -e' setting, any exit status
  # other than zero causes the current shell to terminate with that exit
  # status as well.
  #
  wait "$pid"
done
