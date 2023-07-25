#!/bin/bash

if [ $# -lt 2 ]
  then
    echo "No arguments supplied"
    echo "USAGE: aks-migrate-utils.sh <cluster name> <resource group name>"
    exit 1
fi

cluster_name=$1
resource_group=$2



node_pool_info=$(az aks nodepool list --cluster-name "$cluster_name" --resource-group "$resource_group" | jq '.[] | select(.mode == "User") | select(.tags.CreatedBy == "Terraform") | {name: .name, size: .vmSize, count: .count, zones: .availabilityZones, id: .id}')

n_name=$(echo "$node_pool_info" | jq -r '.name')
n_size=$(echo "$node_pool_info" | jq -r '.size')
n_count=$(echo "$node_pool_info" | jq -r '.count')
n_sub_id=$(echo "$node_pool_info" | jq -r '.id' | cut -d '/' -f 3)
n_zones=$(echo "$node_pool_info" | jq -r '.zones[]' | tr '\n' ' ' |  xargs | sed 's/ /, /g ' )

n_name_new="${n_name}mig"




subscription_name=$(az account subscription show --id "$n_sub_id" | jq -r '.displayName')

echo "-----------------------------------------"


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
--os-type Linux"

echo "NODEPOOL UPDATE (remove taint):  az aks nodepool update \
--cluster-name $cluster_name \
--name $n_name_new \
--resource-group $resource_group \
--node-taints \"\" \
--subscription $subscription_name"
