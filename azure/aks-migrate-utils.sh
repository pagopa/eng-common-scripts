#!/bin/bash

# AKS Migration Utility Script
# 
# Description:
#   This script facilitates the migration of AKS node pools by creating new node pools
#   with the same configuration as existing ones. It's particularly useful for cluster
#   upgrades or node pool migrations.
#
# Prerequisites:
#   - Azure CLI installed and configured
#   - jq installed
#   - Active Azure subscription
#
# Usage:
#   ./aks-migrate-utils.sh <subscription_name> <cluster_name> <resource_group_name>
#
# Parameters:
#   subscription_name  - Azure subscription name where the cluster resides
#   cluster_name      - Name of the AKS cluster
#   resource_group    - Name of the resource group containing the cluster
#
# Example:
#   ./aks-migrate-utils.sh "My Production Subscription" "my-aks-cluster" "my-rg"

# Enable debug mode if DEBUG environment variable is set
if [[ "${DEBUG}" == "true" ]]; then
    set -x
fi

# Function to log messages with emoji
log_info() {
    echo "🔵 INFO: $1"
}

log_success() {
    echo "✅ SUCCESS: $1"
}

log_warning() {
    echo "⚠️  WARNING: $1"
}

log_error() {
    echo "❌ ERROR: $1"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo "🔍 DEBUG: $1"
    fi
}

# Function to check if required commands are available
check_prerequisites() {
    local required_commands=("az" "jq")
    local missing_commands=()

    log_info "Checking prerequisites..."
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "The following required commands are missing:"
        printf '%s\n' "${missing_commands[@]}"
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Function to validate input parameters
validate_inputs() {
    if [ $# -lt 3 ]; then
        log_error "Insufficient arguments supplied"
        echo "Usage: aks-migrate-utils.sh <subscription_name> <cluster_name> <resource_group_name>"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites

# Validate inputs
validate_inputs "$@"

subscription_name="$1"
cluster_name="$2"
resource_group="$3"

# Switch to the specified subscription
log_info "Switching to subscription: $subscription_name"
if ! az account set --subscription "$subscription_name"; then
    log_error "Failed to switch to subscription '$subscription_name'"
    log_info "Available subscriptions:"
    az account list --query "[].name" -o tsv
    exit 1
fi
log_success "Successfully switched to subscription: $subscription_name"

# Get node pools raw data first for debugging
log_info "Fetching node pools data..."
raw_node_pools=$(az aks nodepool list --cluster-name "$cluster_name" --resource-group "$resource_group")
log_debug "Raw node pools data: $raw_node_pools"

# Get filtered node pool information
log_info "Filtering node pools..."
node_pool_info=$(echo "$raw_node_pools" | jq -r '
    .[] | 
    select(.mode == "User") | 
    {
        name: .name, 
        size: .vmSize, 
        count: .count, 
        zones: .availabilityZones, 
        id: .id, 
        labels: .nodeLabels,
        mode: .mode,
        tags: .tags
    }
')

log_debug "Filtered node pool info: $node_pool_info"

if [ -z "$node_pool_info" ]; then
    log_error "No user node pools found in cluster '$cluster_name'"
    log_debug "Available node pools and their modes:"
    echo "$raw_node_pools" | jq -r '.[] | "Name: \(.name), Mode: \(.mode), Tags: \(.tags)"'
    exit 1
fi

log_success "Found node pools:"
echo "$node_pool_info" | jq -r '.name'
echo ""

n_name=$(echo "$node_pool_info" | jq -r '.name')

while IFS= read -r line; do
    log_info "Processing node pool: $line"
    
    n_size=$(echo "$node_pool_info" | jq -r --arg pool_name "$line" 'select(.name == $pool_name) | .size')
    n_count=$(echo "$node_pool_info" | jq -r --arg pool_name "$line" 'select(.name == $pool_name) | .count')
    n_zones=$(echo "$node_pool_info" | jq -r --arg pool_name "$line" 'select(.name == $pool_name) | .zones[]' | tr '\n' ' ' | xargs | sed 's/ / /g')
    n_labels=$(echo "$node_pool_info" | jq -r --arg pool_name "$line" 'select(.name == $pool_name) | .labels | to_entries[] | "\(.key)=\(.value)"')
    
    log_debug "Pool size: $n_size"
    log_debug "Pool count: $n_count"
    log_debug "Pool zones: $n_zones"
    log_debug "Pool labels: $n_labels"

    this_labels=""
    while IFS= read -r label; do
        this_labels="${this_labels} $label"
    done <<< "$n_labels"

    n_name_new="${line}mg"
    echo "-----------------------------------------"
    echo "#### Commands for ${line}"
    echo ""
    echo "NODEPOOL ADD:   az aks nodepool add \\
--cluster-name $cluster_name \\
--name $n_name_new \\
--resource-group $resource_group \\
--node-taints migrationOnly=true:NoSchedule \\
--subscription \"$subscription_name\" \\
--mode User \\
--node-vm-size $n_size \\
--node-count $n_count \\
--zones $n_zones \\
--max-pods 250 \\
--labels ${this_labels:1} \\
--os-type Linux"
    echo ""
    echo "NODEPOOL UPDATE (remove taint):  az aks nodepool update \\
--cluster-name $cluster_name \\
--name $n_name_new \\
--resource-group $resource_group \\
--node-taints \"\" \\
--subscription \"$subscription_name\""

    echo "-----------------------------------------"
    log_success "Generated commands for node pool: $line"
done <<< "$n_name"

log_success "Script completed successfully! 🎉"
