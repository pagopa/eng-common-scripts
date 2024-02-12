#!/bin/bash

# Imposta le opzioni errexit, nounset e pipefail per scrivere codice bash più robusto e sicuro
set -euo pipefail

# Controlla che il primo parametro sia fornito e altrimenti stampa un messaggio di errore e esci dallo script
if [ -z "$1" ]; then
  echo "Usage: $0 subscription"
  exit 1
fi

# Controlla che il comando jq sia installato e altrimenti stampa un messaggio di errore e esci dallo script
if ! command -v jq &> /dev/null; then
  echo "jq is required but not installed. Please install it from [here]."
  exit 1
fi

# Controlla che il comando az sia installato e altrimenti stampa un messaggio di errore e esci dallo script
if ! command -v az &> /dev/null; then
  echo "az is required but not installed. Please install it from [here]."
  exit 1
fi

pids=()
subscription="$1"

# Imposta la subscription di Azure
az account set --subscription "$subscription"

# Ottieni la lista delle container app e dei loro resource group
containerapps=$(az containerapp list --query "[].{name:name, resourceGroup:resourceGroup}")

# Per ogni coppia nome-resource group, assegna le variabili name e resource_group
for containerapp in $(echo "$containerapps" | jq -c '.[]'); do
  name=$(echo "$containerapp" | jq -r ".name")
  resource_group=$(echo "$containerapp" | jq -r ".resourceGroup")
  # Usa le opzioni -e e -n per interpretare i caratteri speciali e non aggiungere una nuova linea alla fine
  echo -e -n "Controllando le revisioni della container app $name nel resource group: $resource_group...\n"
  # Ottieni la lista delle revisioni della container app
  is_failed=$(az containerapp revision list --all --name "$name" --resource-group "$resource_group" --query "[0].properties.runningState == 'Failed'")
  # Controlla che il comando az containerapp revision list abbia avuto successo e altrimenti stampa un messaggio di errore e esci dallo script
  if [ $? -ne 0 ]; then
    echo "Error: failed to get the revision list for container app $name in resource group $resource_group"
    exit 1
  fi
  # Usa le doppie virgolette per espandere la variabile is_failed
  echo "$is_failed"
  # Usa le doppie virgolette per espandere la variabile is_failed e controlla se è uguale a true
  if [ "$is_failed" = "true" ]; then
      echo "Delete container app with name: $name on resourceGroup: $resource_group"
      az containerapp delete --name "$name" --resource-group "$resource_group" --subscription "$subscription" --yes &
      # Controlla che il comando az containerapp delete abbia avuto successo e altrimenti stampa un messaggio di errore e continua il ciclo
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

# Usa le doppie virgolette per espandere l'array pids e iterare su ogni PID
for pid in "${pids[@]}"; do
  # Usa le doppie virgolette per espandere la variabile pid e attendi il termine del processo
  wait "$pid"
  # Controlla che il comando wait abbia avuto successo e altrimenti stampa un messaggio di errore e esci dallo script
  if [ $? -ne 0 ]; then
    echo "Error: failed to wait for process $pid"
    exit 1
  fi
done
