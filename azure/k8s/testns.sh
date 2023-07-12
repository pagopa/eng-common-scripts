#!/bin/bash

# This script retrieves all Kubernetes namespaces (excluding 'kube-system') and checks each one for the presence of a Pod Disruption Budget (PDB) and Anti-Pod Affinity.
# It then outputs a formatted table with each namespace and whether or not it has a PDB and Anti-Pod Affinity defined.

# Ensure kubectl is installed and accessible
if ! command -v kubectl &> /dev/null; then
    echo "kubectl could not be found"
    exit 1
fi

# Get all namespaces
namespaces=$(kubectl get namespaces --no-headers | awk '{print $1}' | grep -v kube-system)

# Check if the namespaces retrieval was successful
if [ $? -ne 0 ]; then
    echo "Failed to retrieve namespaces"
    exit 1
fi

printf "%-20s|%-15s|%-25s\n" "Namespace" "PDB Defined" "Anti-Pod Affinity Defined"

for ns in $namespaces; do

  # Check if Pod Disruption Budget (PDB) is defined
  pdb_defined=$(kubectl get pdb -n $ns 2>&1 | grep -v "No resources found")

  # Check if Anti-Pod Affinity is defined
  affinity_defined=$(kubectl get pod -n $ns -o yaml | grep podAntiAffinity 2>&1)

  if [ -n "$pdb_defined" ]; then
    pdb_status="Yes"
  else
    pdb_status="No"
  fi

  if [ -n "$affinity_defined" ]; then
    affinity_status="Yes"
  else
    affinity_status="No"
  fi

  printf "%-20s|%-15s|%-25s\n" "$ns" "$pdb_status" "$affinity_status"

done
