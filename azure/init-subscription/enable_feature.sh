#!/usr/bin/env bash
set -e

SUBSCRIPTION=$1

if [ -z "${SUBSCRIPTION}" ]; then
    printf "\e[1;31mYou must provide a subscription as first argument.\n"
    exit 1
fi

az account set -s "${SUBSCRIPTION}"

# Feature Flag EncryptionAtHost, EnablePodIdentityPreview
# https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disks-enable-host-based-encryption-cli#prerequisites
# https://learn.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity#register-the-enablepodidentitypreview-feature-flag

az feature register --namespace Microsoft.Compute --name EncryptionAtHost
az feature register --namespace "Microsoft.ContainerService" --name "EnablePodIdentityPreview"

while true; do
    result_encryption=$(az feature show --namespace Microsoft.Compute --name EncryptionAtHost | jq -r .properties.state)
    result_pod_identity=$(az feature show --namespace Microsoft.ContainerService --name EnablePodIdentityPreview | jq -r .properties.state)

    if [ "$result_encryption" == "Registered" ] && [ "$result_pod_identity" == "Registered" ]; then
        echo "[INFO] Feature enabled"
        break
    else
        echo "[INFO] Awaiting feature registration"
        sleep 60
    fi
done

az provider register -n Microsoft.Compute
az provider register -n Microsoft.ContainerService