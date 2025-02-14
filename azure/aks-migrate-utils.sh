#!/bin/bash

#################################################################################
# AKS Node Pool Migration Utility
# Version: 1.0.0
#################################################################################
# ... [header comments rimangono gli stessi] ...

# Enable strict mode
set -euo pipefail
IFS=$'\n\t'

# Script constants
readonly SCRIPT_VERSION="1.0.0"
readonly REQUIRED_COMMANDS=("az" "jq")
readonly MAX_PODS_DEFAULT=250
readonly NODE_POOL_SUFFIX="mg"
readonly NODE_POOL_OS_TYPE="Linux"
readonly INITIAL_TAINT="migrationOnly=true:NoSchedule"

# Function to log messages with emoji
log_info() {
    echo "🔵 INFO: $1" >&2
}

log_success() {
    echo "✅ SUCCESS: $1" >&2
}

log_warning() {
    echo "⚠️  WARNING: $1" >&2
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "🔍 DEBUG: $1" >&2
    fi
}

# Cleanup function
cleanup() {
    log_debug "Performing cleanup..."
    # Add cleanup logic here if needed
}

# Set up error handling
trap cleanup EXIT
trap 'log_error "An error occurred on line $LINENO. Exit code: $?"; exit 1' ERR

# Function to check if required commands are available
check_prerequisites() {
    local missing_commands=()

    log_info "Checking prerequisites..."
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
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
        echo "Usage: ${0} <subscription_name> <cluster_name> <resource_group_name>"
        exit 1
    fi
}

# Function to check Azure CLI login status
check_azure_login() {
    log_info "Checking Azure CLI login status..."
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI login verified"
}

# Function to format and print node pool commands
print_nodepool_commands() {
    # Usiamo nomi diversi per evitare conflitti con le variabili readonly
    local input_pool_name="$1"
    local input_new_pool_name="$2"
    local input_aks_name="$3"
    local input_rg_name="$4"
    local input_sub_name="$5"
    local input_vm_size="$6"
    local input_node_count="$7"
    local input_zones="$8"
    local input_labels="$9"
    local os_disk_size="${10}"

    echo "-----------------------------------------"
    echo "#### Commands for ${input_pool_name}"
    echo ""
    echo "NODEPOOL ADD:"
    echo "az aks nodepool add \\"
    echo "  --cluster-name \"${input_aks_name}\" \\"
    echo "  --name \"${input_new_pool_name}\" \\"
    echo "  --resource-group \"${input_rg_name}\" \\"
    echo "  --node-taints \"${INITIAL_TAINT}\" \\"
    echo "  --subscription \"${input_sub_name}\" \\"
    echo "  --mode User \\"
    echo "  --node-vm-size \"${input_vm_size}\" \\"
    echo "  --node-count \"${input_node_count}\" \\"
    echo "  --zones ${input_zones} \\"
    echo "  --max-pods ${MAX_PODS_DEFAULT} \\"
    echo "  --labels ${input_labels} \\"
    echo "  --node-osdisk-size ${os_disk_size} \\"
    echo "  --os-type ${NODE_POOL_OS_TYPE}"
    echo ""
    echo "NODEPOOL UPDATE (remove taint):"
    echo "az aks nodepool update \\"
    echo "  --cluster-name \"${input_aks_name}\" \\"
    echo "  --name \"${input_new_pool_name}\" \\"
    echo "  --resource-group \"${input_rg_name}\" \\"
    echo "  --node-taints \"\" \\"
    echo "  --subscription \"${input_sub_name}\""
    echo "-----------------------------------------"
}

# Function to process node pools data
process_node_pools() {
    # Usiamo nomi diversi per evitare conflitti con le variabili readonly
    local input_pool_info="$1"
    local input_aks_name="$2"
    local input_rg_name="$3"
    local input_sub_name="$4"

    # Variabili locali per l'elaborazione
    local current_vm_size
    local current_node_count
    local current_zones
    local current_labels
    local current_pool_name

    echo "${input_pool_info}" | jq -r '.name' | while IFS= read -r current_pool_name; do
        log_info "Processing node pool: ${current_pool_name}"

        current_vm_size=$(echo "${input_pool_info}" | jq -r --arg pool_name "${current_pool_name}" 'select(.name == $pool_name) | .size')
        current_node_count=$(echo "${input_pool_info}" | jq -r --arg pool_name "${current_pool_name}" 'select(.name == $pool_name) | .count')
        current_zones=$(echo "${input_pool_info}" | jq -r --arg pool_name "${current_pool_name}" 'select(.name == $pool_name) | .zones[]' | tr '\n' ' ' | xargs)
        current_labels=$(echo "${input_pool_info}" | jq -r --arg pool_name "${current_pool_name}" 'select(.name == $pool_name) | .labels | to_entries[] | "\(.key)=\(.value)"' | tr '\n' ' ')
        current_disk_size=$(echo "${input_pool_info}" | jq -r --arg pool_name "${current_pool_name}" 'select(.name == $pool_name) | .osDiskSizeGb')

        log_debug "Pool details:"
        log_debug "- VM Size: ${current_vm_size}"
        log_debug "- Node Count: ${current_node_count}"
        log_debug "- Zones: ${current_zones}"
        log_debug "- Labels: ${current_labels}"
        log_debug "- OS disk size: ${current_disk_size}"

        print_nodepool_commands \
            "${current_pool_name}" \
            "${current_pool_name}${NODE_POOL_SUFFIX}" \
            "${input_aks_name}" \
            "${input_rg_name}" \
            "${input_sub_name}" \
            "${current_vm_size}" \
            "${current_node_count}" \
            "${current_zones}" \
            "${current_labels}" \
            "$((${current_disk_size} > 250 ? 250 : ${current_disk_size}))"

        log_success "Generated commands for node pool: ${current_pool_name}"
    done
}

main() {
    # Check prerequisites and validate inputs
    check_prerequisites
    check_azure_login
    validate_inputs "$@"

    # Set input parameters as readonly
    readonly SUBSCRIPTION_NAME="$1"
    readonly CLUSTER_NAME="$2"
    readonly RESOURCE_GROUP="$3"

    # Switch to the specified subscription
    log_info "Switching to subscription: ${SUBSCRIPTION_NAME}"
    if ! az account set --subscription "${SUBSCRIPTION_NAME}"; then
        log_error "Failed to switch to subscription '${SUBSCRIPTION_NAME}'"
        log_info "Available subscriptions:"
        az account list --query "[].name" -o tsv
        exit 1
    fi
    log_success "Successfully switched to subscription: ${SUBSCRIPTION_NAME}"

    # Get node pools data
    log_info "Fetching node pools data..."
    local raw_node_pools
    raw_node_pools=$(az aks nodepool list --cluster-name "${CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}")
    log_debug "Raw node pools data: ${raw_node_pools}"

    # Process node pools
    local node_pool_info
    node_pool_info=$(echo "${raw_node_pools}" | jq -r '
        .[] | 
        select(.mode == "User") | 
        {
            name: .name, 
            size: .vmSize, 
            count: .count, 
            zones: .availabilityZones, 
            labels: .nodeLabels,
            mode: .mode,
            tags: .tags,
            osDiskSizeGb: .osDiskSizeGb
        }
    ')

    if [ -z "${node_pool_info}" ]; then
        log_error "No user node pools found in cluster '${CLUSTER_NAME}'"
        exit 1
    fi

    log_success "Found node pools:"
    echo "${node_pool_info}" | jq -r '.name'
    echo ""

    # Process each node pool
    process_node_pools "${node_pool_info}" "${CLUSTER_NAME}" "${RESOURCE_GROUP}" "${SUBSCRIPTION_NAME}"

    log_success "Script completed successfully! 🎉"
}

# Execute main function
main "$@"
