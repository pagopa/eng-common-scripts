# CRON GROM

**Generic Recovery & Outage Mitigator for AKS CronJobs**

---

CRON GROM is a Bash script that automates the detection and mitigation of stuck Kubernetes CronJobs in an Azure Kubernetes Service (AKS) environment.  
When CronJob workloads are unable to schedule (e.g., remain in Pending state) due to resource constraints or incompatible node selectors, CRON GROM suspends the problematic CronJobs and cleans up all related Pending Jobs and Pods, helping restore normal operation with minimal manual intervention.

---

## ⚡ Features

- **Automated Detection:** Finds CronJobs with Jobs that are persistently Pending.
- **Resource & Node Selector Checks:** Determines unschedulable causes (CPU, memory, nodeSelector labels).
- **Automatic Suspension:** Suspends any malfunctioning CronJob to stop further job creation.
- **Cleanup of Pending Workloads:** Deletes all Pending Jobs and their associated Pods.
- **Handles Multi-Container Pods:** Supports Pods with multiple containers.
- **Comprehensive Logging:** Detailed debug and action logs for transparency.
- **Safe and Idempotent:** Only acts when necessary, does not alter healthy CronJobs.

---

## 🚀 Quick Start

### Usage

```bash
bash cron-grom.sh [NAMESPACE]
```

- `NAMESPACE` *(optional)*: Target Kubernetes namespace. Defaults to `default`.

### Help

**Examples:**

```bash
bash cron-grom.sh bash cron-grom.sh my-namespace
```

---

## 🛠️ How It Works

1. **Scan for Jobs:** The script lists all Jobs in the specified namespace and checks which ones are owned by CronJobs.
2. **Identify Pending Pods:** For each CronJob, it finds all Jobs and Pods stuck in `Pending` state.
3. **Check Scheduling Feasibility:** 
    - Evaluates if any AKS node can satisfy the resource requests and nodeSelector for each Pending Pod.
    - Aggregates container requests for full Pod resource requirements.
4. **Mitigate Incidents:**
    - If **no node** can schedule the Pod (due to insufficient resources or label mismatch), the script:
        - **Suspends the CronJob** (`spec.suspend=true`).
        - **Deletes all Pending Jobs** and their `Pending` Pods linked to that CronJob.
5. **Report:** Outputs a summary including suspended CronJobs and the cause.

---

## 🔍 Requirements

- **bash**
- **kubectl** (configured and authenticated for the target AKS cluster)
- **jq**

---

## 🧑‍💻 Example Output

```bash
[ACTION] SUSPENDING CronJob: example-cronjob (no node has sufficient resources for example-pod of job example-job) [CLEANUP] Deleting pending Jobs/Pods for CronJob: example-cronjob Deleting Job: example-job Deleting Pending Pod: example-pod Suspended CronJobs (no possible scheduling found):
- example-cronjob
```

If all CronJobs are healthy, you may see:

```bash
No CronJobs issues. All pending pods are theoretically schedulable.
```

---

## 🤔 Troubleshooting

- Ensure `kubectl` and `jq` are in your `$PATH`.
- Use a KUBECONFIG context with sufficient permissions to read, patch, and delete resources in the target namespace.
- For complex resource issues or cluster failures, deeper Kubernetes or cloud diagnostics may be required.
