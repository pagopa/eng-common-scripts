#!/bin/bash

if [ $# -lt 2 ]
  then
    echo "No arguments supplied"
    echo "USAGE: aks-migrate-utils.sh <cluster name> <resource group name>"
    exit 1
fi

cluster_name=$1
resource_group=$2




node_pool_info=$(az aks nodepool list --cluster-name "$cluster_name" --resource-group "$resource_group" | jq '.[] | select(.mode == "User") | select(.tags.CreatedBy == "Terraform") | {name: .name, size: .vmSize, count: .count, zones: .availabilityZones, id: .id, labels: .nodeLabels}')

echo "nodepool_info $node_pool_info"

n_name=$(echo "$node_pool_info" | jq -r '.name')




while IFS= read -r line; do

  n_size=$(echo "$node_pool_info" | jq -r --arg pool_name $line 'select(.name == $pool_name) | .size')
  n_count=$(echo "$node_pool_info" | jq -r --arg pool_name $line 'select(.name == $pool_name) | .count')
  n_sub_id=$(echo "$node_pool_info" | jq -r --arg pool_name $line 'select(.name == $pool_name) | .id' | cut -d '/' -f 3)
  n_zones=$(echo "$node_pool_info" | jq -r --arg pool_name $line 'select(.name == $pool_name) | .zones[]' | tr '\n' ' ' |  xargs | sed 's/ / /g ' )
  n_labels=$(echo "$node_pool_info" | jq -r --arg pool_name $line 'select(.name == $pool_name) | .labels | to_entries[] | "\(.key)=\(.value)"' )
  subscription_name=$(az account subscription show --id "$n_sub_id" | jq -r '.displayName')

  this_labels=""
  while IFS= read -r label; do
    this_labels="${this_labels} $label"
  done <<< "$n_labels"



  n_name_new="${line}mg"
  echo "-----------------------------------------"
  echo "#### Commands for ${line}"
  echo ""
  echo "NODEPOOL ADD:   az aks nodepool add \
  --cluster-name $cluster_name \
  --name $n_name_new \
  --resource-group $resource_group \
  --node-taints migrationOnly=true:NoSchedule \
  --subscription $subscription_name \
  --mode User \
  --node-vm-size $n_size \
  --node-count $n_count \
  --zones $n_zones \
  --max-pods 250 \
  --labels ${this_labels:1}\
  --os-type Linux"
  echo ""
  echo "NODEPOOL UPDATE (remove taint):  az aks nodepool update \
  --cluster-name $cluster_name \
  --name $n_name_new \
  --resource-group $resource_group \
  --node-taints \"\" \
  --subscription $subscription_name"


echo "-----------------------------------------"
done <<< "$n_name"







