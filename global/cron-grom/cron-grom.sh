#!/bin/bash

################################################################################
#  ██████╗ ██████╗  ██████╗ ███╗   ██╗      ██████╗ ██████╗  ██████╗ ███╗   ███╗
# ██╔════╝ ██╔══██╗██╔═══██╗████╗  ██║     ██╔════╝ ██╔══██╗██╔═══██╗████╗ ████║
# ██║      ██████╔╝██║   ██║██╔██╗ ██║     ██║  ███╗██████╔╝██║   ██║██╔████╔██║
# ██║      ██╔══██╗██║   ██║██║╚██╗██║     ██║   ██║██╔══██╗██║   ██║██║╚██╔╝██║
# ╚██████╔ ██║  ██║╚██████╔╝██║ ╚████║     ╚██████╔╝██║  ██║╚██████╔╝██║ ╚═╝ ██║
#  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
# ------------------------------------------------------------------------------
# CRON GROM - Generic Recovery & Outage Mitigator for AKS CronJobs
#
# This script repairs CronJobs in the AKS cluster in case of incidents
# with many Pending jobs.
#
# Usage:
#   ./cronjob-grom.sh [NAMESPACE]
#
# Arguments:
#   NAMESPACE     The target Kubernetes namespace (default: default)
#
# Description:
#   This script identifies CronJobs which are repeatedly stuck in Pending state
#   due to:
#     - Resource limits (requested CPU and/or memory unavailable on any node)
#     - nodeSelector incompatibility (no node matches scheduling requirements)
#
#   For any such CronJob encountered, the script:
#     1. Suspends the CronJob (sets spec.suspend = true)
#     2. Cleans up all associated Pending Jobs and Pods created by that CronJob
#
#   The script supports multi-container Pods and performs nodeSelector checks.
#
# Requirements:
#   - bash
#   - kubectl
#   - jq
#
################################################################################

show_help() {
  echo "-------------------------------------------------------------------------------"
  echo "CRON GROM - Generic Recovery & Outage Mitigator for AKS CronJobs"
  echo "-------------------------------------------------------------------------------"
  echo ""
  echo "Usage:"
  echo "  bash cronjob-grom.sh [soft|fix|resume] [NAMESPACE]"
  echo ""
  echo "Arguments:"
  echo "  MODE                Operation mode [soft|fix|resume]."
  echo "  NAMESPACE           (optional) The Kubernetes namespace (default: default)."
  echo ""
  echo "Description:"
  echo "  soft   - Only suspends CronJobs with pending pods above the threshold and cleans them up."
  echo "  fix    - Immediately suspends CronJobs with at least 1 pending pod and cleans them up."
  echo "  resume - Resumes suspended CronJobs."
  echo ""
  echo "Examples:"
  echo "  bash cronjob-grom.sh soft"
  echo "  bash cronjob-grom.sh soft my-namespace"
  echo "  bash cronjob-grom.sh fix"
  echo "  bash cronjob-grom.sh resume"
  echo ""
  echo "Help:"
  echo "  bash cronjob-grom.sh -h"
  echo "  bash cronjob-grom.sh --help"
  echo ""
}


if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

MODE="${1:-soft}"
NAMESPACE="${2:-default}"
PENDING_THRESHOLD=1

# Check for valid MODE
if [[ "$MODE" != "soft" && "$MODE" != "fix" && "$MODE" != "resume" ]]; then
  echo "Error: invalid mode ('$MODE'). Choose between soft, fix, resume."
  show_help
  exit 1
fi

# Check for required tools
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found."
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found."
  exit 1
fi

# Convert CPU requests to millicores (For example: 2 -> 2000, 500m -> 500)
cpu2m() {
  [[ $1 == *m ]] && echo "${1%m}" || echo "$(( ${1:-0} * 1000 ))"
}

# Convert memory requests to Mi (For example: 1Gi -> 1024, 512Mi -> 512, etc.)
mem2mi() {
  [[ $1 == *Mi ]] && echo "${1%Mi}" && return
  [[ $1 == *Gi ]] && echo "$(( ${1%Gi} * 1024 ))" && return
  [[ $1 == *Ki ]] && echo "$(( ${1%Ki} / 1024 ))" && return
  [[ $1 == *M ]] && echo "$(( ${1%M} * 1000 / 1024 ))" && return
  [[ $1 == *G ]] && echo "$(( ${1%G} * 1000 * 1000 / 1024 ))" && return
  [[ $1 == *K ]] && echo "$(( ${1%K} / 1024 ))" && return
  echo "${1:-0}"
}


JOBS=$(kubectl get jobs -n "$NAMESPACE" -o json)
SUSPENDED=()

case "$MODE" in
  soft)
    # Iterate over all jobs in the namespace
    for row in $(echo "$JOBS" | jq -r '.items[] | @base64'); do
      _jqj() { echo "$row" | base64 --decode | jq -r "${1}"; }
      JOB_NAME=$(_jqj '.metadata.name')
      OWNER_KIND=$(_jqj '.metadata.ownerReferences[0].kind // ""')
      OWNER_NAME=$(_jqj '.metadata.ownerReferences[0].name // ""')
      [ "$OWNER_KIND" != "CronJob" ] && continue

      PODS=$(kubectl get pods -n "$NAMESPACE" --selector=job-name="$JOB_NAME" -o json)
      PENDING_COUNT=$(echo "$PODS" | jq '[.items[]|select(.status.phase=="Pending")]|length')
      [ "$PENDING_COUNT" -eq 0 ] && continue

      # Iterate over all pods in Pending state for this job
      for podrow in $(echo "$PODS" | jq -r '.items[] | select(.status.phase=="Pending") | @base64'); do
        _jq() { echo "$podrow" | base64 --decode | jq -r "${1}"; }
        POD_NAME=$(_jq '.metadata.name')

        # Sum the CPU and memory requests of all containers in the pending pod
        TOTAL_POD_CPU_M=0
        TOTAL_POD_MEM_MI=0
        CONTAINERS_LENGTH=$(_jq '.spec.containers | length')
        for ((i=0; i<CONTAINERS_LENGTH; i++)); do
          CON_CPU=$(_jq ".spec.containers[$i].resources.requests.cpu // \"0\"")
          CON_MEM=$(_jq ".spec.containers[$i].resources.requests.memory // \"0\"")
          CPU_M=$(cpu2m "$CON_CPU")
          MEM_MI=$(mem2mi "$CON_MEM")
          TOTAL_POD_CPU_M=$(( TOTAL_POD_CPU_M + CPU_M ))
          TOTAL_POD_MEM_MI=$(( TOTAL_POD_MEM_MI + MEM_MI ))
        done

        CAN_SCHEDULE=false
        NO_NODE_MATCH_SELECTOR=true
        NODES=$(kubectl get nodes -o json)

        # Iterate over all nodes to find a suitable one for scheduling
        for noderow in $(echo "$NODES" | jq -r '.items[] | @base64'); do
          _jqn() { echo "$noderow" | base64 --decode | jq -r "${1}"; }
          NODE_NAME=$(_jqn '.metadata.name')
          NODE_LABELS=$(kubectl get node "$NODE_NAME" -o json | jq -r '.metadata.labels')
          NODE_CPU=$(_jqn '.status.allocatable.cpu')
          NODE_MEM=$(_jqn '.status.allocatable.memory')
          NODE_CPU_M=$(cpu2m "$NODE_CPU")
          NODE_MEM_MI=$(mem2mi "$NODE_MEM")
          # nodeSelector check
          POD_NODESELECTOR=$(_jq '.spec.nodeSelector // {}')
          SELECTOR_OK=true
          for key in $(echo "$POD_NODESELECTOR" | jq -r 'keys[]'); do
            required_value=$(echo "$POD_NODESELECTOR" | jq -r ".\"$key\"")
            node_value=$(echo "$NODE_LABELS" | jq -r ".\"$key\" // empty")
            if [[ "$node_value" != "$required_value" ]]; then
              SELECTOR_OK=false
              break
            fi
          done
          if [[ "$SELECTOR_OK" == true ]]; then
            NO_NODE_MATCH_SELECTOR=false
          else
            continue
          fi

          PODS=$(kubectl get pods -n "$NAMESPACE" --selector=job-name="$JOB_NAME" -o json)
          PENDING_COUNT=$(echo "$PODS" | jq '[.items[]|select(.status.phase=="Pending")]|length')
          [ "$PENDING_COUNT" -ge "$PENDING_THRESHOLD" ] && CAN_SCHEDULE=false && break

          # Calculate available resources on this node
          NODE_PODS_JSON=$(kubectl get pods --all-namespaces -o json --field-selector=spec.nodeName="$NODE_NAME",status.phase=Running)
          USED_CPU_M=$(echo "$NODE_PODS_JSON" | jq '
            [
              .items[].spec.containers[]?.resources.requests.cpu // "0"
              | if endswith("m") then sub("m";"")|tonumber else (tonumber * 1000) end
            ] | add // 0
          ')
          USED_MEM_MI=$(echo "$NODE_PODS_JSON" | jq '
            [
              .items[].spec.containers[]?.resources.requests.memory // "0"
              | if endswith("Mi") then sub("Mi";"")|tonumber
                elif endswith("Gi") then sub("Gi";"")|tonumber * 1024
                elif endswith("Ki") then (sub("Ki";"")|tonumber/1024|floor)
                else tonumber
                end
            ] | add // 0
          ')
          AVAIL_CPU_M=$(( NODE_CPU_M - USED_CPU_M ))
          AVAIL_MEM_MI=$(( NODE_MEM_MI - USED_MEM_MI ))
          echo "[DEBUG] Node $NODE_NAME: availCPU=${AVAIL_CPU_M}m availMEM=${AVAIL_MEM_MI}Mi | Needs: ${TOTAL_POD_CPU_M}m ${TOTAL_POD_MEM_MI}Mi"
          if (( AVAIL_CPU_M >= TOTAL_POD_CPU_M && AVAIL_MEM_MI >= TOTAL_POD_MEM_MI )); then
            CAN_SCHEDULE=true
            break
          fi
        done

        # Take action if the pod cannot be scheduled
        if [[ "$CAN_SCHEDULE" == false ]]; then
          if [[ "$NO_NODE_MATCH_SELECTOR" == true ]]; then
            echo "[ACTION] SUSPENDING CronJob: $OWNER_NAME (no node matches the nodeSelector required by $POD_NAME for job $JOB_NAME)"
          else
            echo "[ACTION] SUSPENDING CronJob: $OWNER_NAME (no node has sufficient resources for $POD_NAME of job $JOB_NAME)"
          fi
          # Suspend the CronJob
          kubectl patch cronjob "$OWNER_NAME" -n "$NAMESPACE" -p '{"spec":{"suspend":true}}' --type=merge
          SUSPENDED+=("$OWNER_NAME")

          # CLEANUP: Delete all pending jobs and pods related to the just suspended CronJob
          echo "[CLEANUP] Deleting pending Jobs/Pods for CronJob: $OWNER_NAME"
          JOBS_TO_DELETE=$(kubectl get jobs -n "$NAMESPACE" -o json | jq -r \
            --arg OWNER "$OWNER_NAME" '
              .items[]
              | select(.metadata.ownerReferences[]?.name == $OWNER)
              | .metadata.name
            ')
          for JOB_TO_DEL in $JOBS_TO_DELETE; do
            echo "  Deleting Job: $JOB_TO_DEL"
            kubectl delete job "$JOB_TO_DEL" -n "$NAMESPACE" --ignore-not-found
            PODS_TO_DEL=$(kubectl get pods -n "$NAMESPACE" --selector=job-name="$JOB_TO_DEL" -o json | jq -r '.items[] | select(.status.phase=="Pending") | .metadata.name')
            for POD_TO_DEL in $PODS_TO_DEL; do
              echo "    Deleting Pending Pod: $POD_TO_DEL"
              kubectl delete pod "$POD_TO_DEL" -n "$NAMESPACE" --ignore-not-found
            done
          done
        else
          echo "[OK] At least one node can schedule pod $POD_NAME of job $JOB_NAME"
        fi
      done
    done
  ;;
  fix)
    CRONJOBS=$(kubectl get cronjobs -n "$NAMESPACE" -o json)
    PODS=$(kubectl get pods -n "$NAMESPACE" -o json)

    SUSPENDED=()
    # 1. Suspend all CronJobs with at least one pending pod
    for row in $(echo "$CRONJOBS" | jq -r '.items[] | @base64'); do
      _jqc() { echo "$row" | base64 --decode | jq -r "${1}"; }
      CRONJOB_NAME=$(_jqc '.metadata.name')

      PENDING_POD_COUNT=$(echo "$PODS" | jq -r --arg cj "$CRONJOB_NAME" '
        .items[]
        | select(.status.phase=="Pending")
        | select(.metadata.ownerReferences[0].kind=="Job")
        | select(.metadata.ownerReferences[0].name|startswith($cj + "-"))
        | .metadata.name' | grep -c . || true)

      echo "[$MODE] Suspending CronJob $CRONJOB_NAME (has $PENDING_POD_COUNT pending pod(s))"
      kubectl patch cronjob "$CRONJOB_NAME" -n "$NAMESPACE" --type=merge -p '{"spec":{"suspend":true}}'
      SUSPENDED+=("$CRONJOB_NAME")
    done

    # 2. Delete all Jobs which have at least one Pending pod
    JOBS_WITH_PENDING_PODS=$(echo "$PODS" | jq -r '
      .items[]
      | select(.status.phase=="Pending")
      | select(.metadata.ownerReferences[0].kind=="Job")
      | .metadata.ownerReferences[0].name' | sort | uniq)

    for JOB_NAME in $JOBS_WITH_PENDING_PODS; do
      echo "Deleting job with pending pod(s): $JOB_NAME"
      kubectl delete job "$JOB_NAME" -n "$NAMESPACE"
    done

    if [ ${#SUSPENDED[@]} -gt 0 ]; then
      echo ""
      echo "Suspended CronJobs:"
      for cj in "${SUSPENDED[@]}"; do
        echo " - $cj"
      done
      echo "Please check their status before running RESUME."
    else
      echo "No CronJobs suspended."
    fi
    ;;
  resume)
    # Resume all suspended cronjobs in the namespace
    CRONJOBS=$(kubectl get cronjob -n "$NAMESPACE" -o json \
      | jq -r '.items[] | select(.spec.suspend==true) | .metadata.name')
    if [[ -z "$CRONJOBS" ]]; then
      echo "No suspended CronJob to resume."
      exit 0
    fi
    for cj in $CRONJOBS; do
      echo "Resuming CronJob $cj"
      kubectl patch cronjob "$cj" -n "$NAMESPACE" --type=merge -p '{"spec":{"suspend":false}}'
    done
    echo "All suspended CronJobs have been resumed."
    ;;
esac
