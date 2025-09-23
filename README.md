# Quick Ordering System Kubernetes Deployment

## Objective

This project provides a comprehensive Kubernetes deployment solution for the `quick-ordering-system` and the `quick-ordering-cloud` project. Through Kubernetes, the deployment of the project can be easily managed and scaled. Further with a CI/CD pipeline using Gitlab, and eventually deployed on AWS EKS. Kind (Kubernetes in Docker) in this repo is being used first for local testing and development.

All manifests files related to the deployment are stored including deployments, services, configmaps, secrets, ingress, MongoDB StatefulSet, and storage components. They are source controlled and can be easily modified and versioned. Also all related important commands required for deployment are also recorded in this repository to facilitate future deployment process.

## Quick Start

### Option 1: Helm Deployment (Recommended)

For a streamlined deployment using Helm charts:

```bash
# Navigate to the Helm chart directory
cd qos/charts/quick-order-system

# Install the complete QOS application with default values
helm install qos . --create-namespace --namespace qos

# Or install with custom values file
helm install qos . -f values-production.yaml --create-namespace --namespace qos
```

### Install for development (uses provided values-development.yaml)

```bash
helm install qos-dev . -f values-development.yaml --namespace qos-dev --create-namespace
```

### Install for production (recommended: create TLS secret externally)

#### 1) Create TLS secret (replace cert/key paths with real files)

```bash
kubectl create secret tls qos-frontend-tls-secret-prod \
  --cert=./certificates/prod-cert.pem \
  --key=./certificates/prod-key.pem \
  -n qos-prod
```
#### 2) Install with production values

```bash
helm install qos-prod . -f values-production.yaml \
  --namespace qos-prod --create-namespace
```

### Option 2: Traditional Manifest Deployment

Prefer Helm. If you need manual (non-Helm) steps, see Appendix A: Manual Deployment. The `qos-depl.sh` script can also orchestrate a full manual deployment.

## Helm Deployment Guide

### Prerequisites

Before deploying with Helm, ensure you have:

1. **Helm 3.x installed** - [Installation Guide](https://helm.sh/docs/intro/install/)
2. **Kubernetes cluster running** (Kind, Minikube, or cloud provider)
3. **kubectl configured** to connect to your cluster
4. **NGINX Ingress Controller** (for ingress functionality)

```bash
# Verify Helm installation
helm version

# Verify kubectl connection
kubectl cluster-info
```

### Set up development or production environment

- Development (no TLS by default):
  - values-development.yaml is included in the chart
  - Single replicas, smaller resources, TLS disabled
  - Command:
    - `helm install qos-dev . -f values-development.yaml --namespace qos-dev --create-namespace`

- Production (TLS enabled, manage TLS externally):
  - values-production.yaml is included in the chart
  - Multiple replicas, larger resources, TLS enabled
  - Create TLS secret externally (recommended) and keep `tls.frontend.manageSecret: false`
  - Command:
    - `kubectl create secret tls qos-frontend-tls-secret-prod --cert=./certificates/prod-cert.pem --key=./certificates/prod-key.pem -n qos-prod`
    - `helm install qos-prod . -f values-production.yaml --namespace qos-prod --create-namespace`

### TLS secret management options

- Helm-managed (development / demo only)
  - Set `tls.frontend.manageSecret: true` and provide base64 `tls.frontend.crt`/`key`
- Externally managed (recommended for production)
  - Leave `manageSecret: false` and create secret with kubectl or cert-manager

### Helm Chart Structure

The QOS Helm chart is located at `qos/charts/quick-order-system/` and includes:

```
quick-order-system/
├── Chart.yaml                 # Chart metadata
├── values.yaml                # Default configuration values
└── templates/                 # Kubernetes manifest templates
    ├── NOTES.txt              # Post-install notes
    ├── _helpers.tpl           # Template helpers
    ├── gitlab-regcred.yaml    # Private registry pull secret (templated)
    ├── mongodb-*.yaml         # MongoDB ConfigMap/StatefulSet/Service/Storage
    ├── qos-backend-*.yaml     # Backend Deployment/Service/ConfigMap
    ├── qos-frontend-*.yaml    # Frontend Deployment/Services/Ingress/TLS
    └── qos-*.yaml             # Shared ConfigMap/Secrets
```

#### Templated values overview

- ingress.frontend → templates/qos-frontend-ingress.yaml (className, host, tls.secretName, paths)
- tls.frontend (optional) → templates/qos-frontend-tls-secret.yaml (crt/key when provided)
- secrets.qos → templates/qos-secret-from-env.yaml (DB creds, cert/key paths, docker registry)
- secrets.gitlab → templates/gitlab-regcred.yaml (dockerconfigjson content)
- secrets.mongodb.app → templates/mongodb-secret.yaml (app user/password)
- mongodb.image/resources/statefulset → templates/mongodb-statefulset.yaml (image, replicas, PVC size)
- mongodb.storage.* → templates/mongodb-storage.yaml (StorageClass + PVs)
- qos-frontend.depl.* → templates/qos-frontend-depl.yaml (replicas, image, resources)
- qos-frontend.service.* → templates/qos-frontend-svc.yaml & qos-frontend-cip-svc.yaml
- qos-backend.depl.* / qos-backend.service.* → templates/qos-backend-depl.yaml & qos-backend-svc.yaml


### Basic Helm Operations

#### Install the Application

```bash
# Navigate to the chart directory
cd qos/charts/quick-order-system

# Install with default values
helm install qos . --create-namespace --namespace qos

# Install with custom values file
helm install qos . -f values-production.yaml --namespace qos

# Install with inline value overrides
helm install qos . --set mongodb.statefulset.replicas=3 --set qos-frontend.depl.spec.replicas=3 --namespace qos
```

#### Upgrade the Application

```bash
# Upgrade with new values
helm upgrade qos . -f values-production.yaml --namespace qos

# Upgrade with inline overrides
helm upgrade qos . --set qos-frontend.depl.template.spec.containers.image=registry.gitlab.com/YOUR_USERNAME/YOUR_PROJECT/frontend:YOUR_VERSION --namespace qos

# Upgrade and wait for rollout completion
helm upgrade qos . -f values-production.yaml --namespace qos --wait --timeout=10m
```

#### Manage Releases

```bash
# List all Helm releases
helm list --all-namespaces

# Get release status
helm status qos --namespace qos

# Get release history
helm history qos --namespace qos

# Rollback to previous version
helm rollback qos --namespace qos

# Rollback to specific revision
helm rollback qos 2 --namespace qos
```

#### Uninstall the Application

```bash
# Uninstall the release (keeps namespace)
helm uninstall qos --namespace qos

# Uninstall and delete namespace
helm uninstall qos --namespace qos
kubectl delete namespace qos
```

### Configuration Management

Create separate values files for different environments (e.g. `values-development.yaml`, `values-production.yaml`), refer to `values-production.example.yaml` and `values-development.example.yaml` for details.

`values-development.yaml` and `values-production.yaml` are not versioned due to sensitive information. Use `values-development.example.yaml` and `values-production.example.yaml` as templates and create your own.

#### Deploy with Environment-Specific Values

```bash
# Development deployment
helm install qos-dev . -f values-development.yaml --namespace qos-dev --create-namespace

# Production deployment
helm install qos-prod . -f values-production.yaml --namespace qos-prod --create-namespace
```

### Common Configuration Updates

#### Update Application Images

```bash
# Update frontend image
helm upgrade qos . --set qos-frontend.depl.template.spec.containers.image=registry.gitlab.com/YOUR_USERNAME/YOUR_PROJECT/frontend:YOUR_VERSION --namespace qos

# Update backend image
helm upgrade qos . --set qos-backend.depl.template.spec.containers.image=registry.gitlab.com/YOUR_USERNAME/YOUR_PROJECT/backend:YOUR_VERSION --namespace qos


# Update both images
helm upgrade qos . \
  --set qos-frontend.depl.template.spec.containers.image=registry.gitlab.com/YOUR_USERNAME/YOUR_PROJECT/frontend:YOUR_VERSION \
  --set qos-backend.depl.template.spec.containers.image=registry.gitlab.com/YOUR_USERNAME/YOUR_PROJECT/backend:YOUR_VERSION \
  --namespace qos
```

## Secrets quick reference

This chart supports two approaches
- Helm-managed (convenient for development)
- Externally managed (recommended for production)
- GitLab registry pull secret
  - Values path: `secrets.gitlab.{name,server,username,password}`
  - Helm-managed (development):
    ```bash
    helm upgrade --install qos . \
      --set secrets.gitlab.name=qos-gitlab-regcred \
      --set secrets.gitlab.server=registry.gitlab.com \
      --set secrets.gitlab.username=k8s \
      --set secrets.gitlab.password=<TOKEN> \
      -n qos --create-namespace
    ```
  - External (production):
    ```bash
    kubectl create secret docker-registry qos-gitlab-regcred \
      --docker-server=registry.gitlab.com \
      --docker-username=k8s \
      --docker-password=<TOKEN> \
      -n qos --dry-run=client -o yaml | kubectl apply -f -
    ```

- Application secret (QOS)
  - Template: `templates/qos-secret-from-env.yaml`
  - Values path: `secrets.qos.{name,database.user,database.password,dockerRegistry,cert,privateKey,user}`
  - Helm-managed by default (created on install). Override per env in values files or via `--set`.

- MongoDB app secret
  - Template: `templates/mongodb-secret.yaml`
  - Secret name: `qos-mongodb-secret`
  - Values path: `secrets.mongodb.app.{user,password}`
  - Helm-managed by default (created on install).

- Frontend TLS secret
  - Referenced by ingress at: `ingress.frontend.tls.secretName`
  - Helm-managed (dev/demo only): set `tls.frontend.manageSecret: true` and provide base64 `tls.frontend.{crt,key}`
  - External (recommended for prod):
    ```bash
    kubectl create secret tls <secretName> \
      --cert=./certs/prod-cert.pem \
      --key=./certs/prod-key.pem \
      -n qos --dry-run=client -o yaml | kubectl apply -f -
    ```

**Tip: Do not commit real secrets. For production, consider External Secrets Operator or Sealed Secrets.**

## Namespace strategy

Recommended: one namespace per environment for isolation and predictable operations.

- Suggested pattern
  - `qos-dev`, `qos-staging`, `qos-prod`
- Benefits
  - Isolation of resources and RBAC
  - Separate quotas/limits and cost controls
  - Easier rollbacks and env-specific cleanup
  - Safer network policies per environment
- Helm usage
  - Install per namespace with `--namespace <ns> --create-namespace`
  - Keep release names environment-specific if desired (e.g., `qos-dev`, `qos-prod`)
  - Example:
    ```bash
    helm install qos-dev . -f values-development.yaml -n qos-dev --create-namespace
    helm install qos-prod . -f values-production.yaml -n qos-prod --create-namespace
    ```
- Notes
  - Using `default` works but is discouraged for production
  - Cross-namespace service access requires full DNS (e.g., `svc.namespace.svc.cluster.local`)

## Scale Applications

```bash
# Scale frontend replicas
helm upgrade qos . --set qos-frontend.depl.spec.replicas=5 --namespace qos

# Scale backend replicas
helm upgrade qos . --set qos-backend.depl.spec.replicas=3 --namespace qos

# Scale MongoDB (StatefulSet)
helm upgrade qos . --set mongodb.statefulset.replicas=3 --namespace qos
```

### Update Resource Limits

```bash
# Update frontend resources
helm upgrade qos . \
  --set qos-frontend.depl.template.spec.containers.resources.requests.cpu=200m \
  --set qos-frontend.depl.template.spec.containers.resources.requests.memory=128Mi \
  --set qos-frontend.depl.template.spec.containers.resources.limits.cpu=500m \
  --set qos-frontend.depl.template.spec.containers.resources.limits.memory=256Mi \
  --namespace qos
```

### Update Configuration Values

```bash
# Update database name
helm upgrade qos . --set database.name=quick-order-system-new --namespace qos

# Update domain configuration
helm upgrade qos . \
  --set application.domains.api.prod=api.newdomain.com \
  --set application.domains.frontend.prod=newdomain.com \
  --namespace qos

# Update MongoDB storage size
helm upgrade qos . --set mongodb.statefulset.volumeClaimTemplates.spec.resources.requests.storage=20Gi --namespace qos
```

## Troubleshooting Helm Deployments

### Debug Helm Issues

```bash
# Dry run to see what would be deployed
helm install qos . --dry-run --debug --namespace qos

# Template rendering (see generated manifests)
helm template qos . --namespace qos

# Get all values (including defaults)
helm get values qos --namespace qos --all

# Get deployed manifests
helm get manifest qos --namespace qos
```

### Common Helm Issues

1. **Values not taking effect**: Ensure proper YAML indentation and use `helm get values` to verify
2. **Template errors**: Use `helm template` to debug template rendering issues
3. **Resource conflicts**: Check for existing resources with `kubectl get all -n qos`
4. **Permission issues**: Verify RBAC permissions and service account configurations

## Advanced Helm Usage

### Using Helm Hooks

The chart supports Helm hooks for advanced deployment scenarios:


Note: If you deploy using Helm (recommended), you can skip the manual steps in this chapter (MongoDB security scripting, kind pre-configuration tips, manual regcred creation, etc.). Use the Helm sections above instead.

```yaml
# In templates, add annotations for hooks
metadata:
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
```

### Chart Dependencies

If you need to add dependencies (like external MongoDB):

```yaml
# In Chart.yaml
dependencies:
  - name: mongodb
    version: 13.x.x
    repository: https://charts.bitnami.com/bitnami
    condition: mongodb.enabled
```

```bash
# Update dependencies
helm dependency update
```

## Helm Monitoring and Maintenance

### Monitoring Helm Deployments

#### Check Deployment Status

```bash
# Monitor release status
helm status qos --namespace qos

# Watch deployment progress
kubectl get pods -n qos -w

# Check all resources in namespace
kubectl get all -n qos

# Monitor specific deployments
kubectl rollout status deployment/qos-frontend-depl -n qos
kubectl rollout status deployment/qos-backend-depl -n qos
kubectl rollout status statefulset/mongodb -n qos
```

#### View Logs

```bash
# View frontend logs
kubectl logs -l app=qos-frontend-pod -n qos --tail=100 -f

# View backend logs
kubectl logs -l app=qos-backend-pod -n qos --tail=100 -f

# View MongoDB logs
kubectl logs -l app=mongodb -n qos --tail=100 -f

# View logs from specific pod
kubectl logs qos-frontend-depl-xxx-xxx -n qos -f
```

### Backup and Recovery

#### Backup Helm Configuration

```bash
# Export current values
helm get values qos --namespace qos > qos-current-values.yaml

# Export all release information
helm get all qos --namespace qos > qos-release-backup.yaml

# Backup MongoDB data (if using persistent volumes)
kubectl exec -n qos mongodb-0 -- mongodump --out /tmp/backup
kubectl cp qos/mongodb-0:/tmp/backup ./mongodb-backup
```

#### Recovery Procedures

```bash
# Restore from backup values
helm upgrade qos . -f qos-current-values.yaml --namespace qos

# Restore MongoDB data
kubectl cp ./mongodb-backup qos/mongodb-0:/tmp/restore
kubectl exec -n qos mongodb-0 -- mongorestore /tmp/restore
```

### Performance Tuning

#### Resource Optimization

```bash
# Monitor resource usage
kubectl top pods -n qos
kubectl top nodes

# Update resource limits based on usage
helm upgrade qos . \
  --set qos-frontend.depl.template.spec.containers.resources.requests.cpu=150m \
  --set qos-frontend.depl.template.spec.containers.resources.requests.memory=96Mi \
  --namespace qos
```

#### Enable Autoscaling

```bash
# Enable frontend autoscaling
helm upgrade qos . \
  --set autoscaling.frontend.enabled=true \
  --set autoscaling.frontend.minReplicas=2 \
  --set autoscaling.frontend.maxReplicas=10 \
  --set autoscaling.frontend.targetCPUUtilizationPercentage=70 \
  --namespace qos
```

### Security Updates

#### Update Secrets

```bash
# Update GitLab registry credentials
kubectl create secret docker-registry qos-gitlab-regcred \
  --docker-server=registry.gitlab.com \
  --docker-username=k8s \
  --docker-password=NEW_TOKEN \
  --dry-run=client -o yaml | kubectl apply -n qos -f -

# Restart deployments to pick up new secrets
kubectl rollout restart deployment/qos-frontend-depl -n qos
kubectl rollout restart deployment/qos-backend-depl -n qos
```

#### Update TLS Certificates

```bash
# Update TLS secret
kubectl create secret tls qos-frontend-tls-secret \
  --cert=./certificates/new-cert.pem \
  --key=./certificates/new-key.pem \
  -n qos --dry-run=client -o yaml | kubectl apply -f -
```

### Maintenance Windows

#### Planned Maintenance

```bash
# Scale down applications for maintenance
helm upgrade qos . \
  --set qos-frontend.depl.spec.replicas=0 \
  --set qos-backend.depl.spec.replicas=0 \
  --namespace qos

# Perform maintenance tasks...

# Scale back up
helm upgrade qos . \
  --set qos-frontend.depl.spec.replicas=2 \
  --set qos-backend.depl.spec.replicas=2 \
  --namespace qos
```

#### Rolling Updates

```bash
# Perform rolling update with zero downtime
helm upgrade qos . -f values-production.yaml --namespace qos --wait

# Monitor rolling update
kubectl rollout status deployment/qos-frontend-depl -n qos
kubectl rollout status deployment/qos-backend-depl -n qos
```

## Appendix A: Manual Deployment (Non-Helm)

If you prefer to deploy components without Helm, follow this appendix. Helm users can skip this section.

#### Useful K8S plugins

Below are some useful plugins that can be used to enhance the k8s experience. You will need to install krew first. Refer to "References" section for more details.

- [neat](https://github.com/evanphx/kube-neat) - A tool to clean up the output of `kubectl get` commands or output of some default values, runtime information and internal fields for more human readable output. (Windows not supported)

### A1. Prerequisites
- kubectl configured
- Namespace created: `kubectl create ns qos` (or use your own and add `-n <ns>` to commands)
- NGINX Ingress Controller installed (Kind/Minikube/cloud)

### A2. Deployment order
1) Secrets and ConfigMaps
2) Storage (PV/StorageClass)
3) Services
4) MongoDB StatefulSet
5) App Deployments (frontend, backend)
6) Ingress

### A3. MongoDB security
- Production (recommended): use the script for secure secrets
  ```bash
  ./create-mongodb-secret.sh
  ```
- Development only: default/dev credentials acceptable

### A4. Create ConfigMaps and Secrets
```bash
# QOS app ConfigMap
kubectl apply -f ./qos/manifests/qos-cfgmap-from-env.yaml -n qos

# QOS backend ConfigMap (datasources)
kubectl apply -f ./qos/manifests/qos-backend-cfgmap.yaml -n qos

# MongoDB ConfigMap (config + init scripts)
kubectl apply -f ./qos/manifests/mongodb-cfgmap.yaml -n qos

# QOS app Secret (update real values first)
kubectl apply -f ./qos/manifests/qos-secret-from-env.yaml -n qos
```

### A5. Storage and MongoDB
```bash
# Storage (PV/SC as applicable)
kubectl apply -f ./qos/manifests/mongodb-storage.yaml -n qos

# MongoDB StatefulSet
kubectl apply -f ./qos/manifests/mongodb-statefulset.yaml -n qos
```

### A6. Services
```bash
kubectl apply -f ./qos/manifests/qos-frontend-svc.yaml -n qos
kubectl apply -f ./qos/manifests/qos-frontend-cip-svc.yaml -n qos
kubectl apply -f ./qos/manifests/qos-backend-svc.yaml -n qos
kubectl apply -f ./qos/manifests/mongodb-service.yaml -n qos
```

### A7. TLS and Ingress
- Production: create TLS secret from real certs
```bash
kubectl create secret tls qos-frontend-tls-secret \
  --cert=./qos/certificates/cert.pem \
  --key=./qos/certificates/key.pem \
  -n qos --dry-run=client -o yaml | kubectl apply -f -

# Ingress
kubectl apply -f ./qos/manifests/qos-frontend-ingress.yaml -n qos
```

### A8. Application Deployments
```bash
# Frontend & Backend
kubectl apply -f ./qos/manifests/qos-frontend-depl.yaml -n qos
kubectl apply -f ./qos/manifests/qos-backend-depl.yaml -n qos
```

### A9. Automated script (optional)
```bash
# Complete deployment with script
./qos-depl.sh

# Clean or verify
./qos-depl.sh --clean
./qos-depl.sh --verify
```

### A10. Notes and tips
- Kind tuning (node labels, ports) and file-descriptor limits: see Troubleshooting
- Private registry credentials (regcred): see the "Set up private registry credentials" section


## References

### Useful commands

```bash
# Check currently active k8s cluster
kubectl config get-contexts

# Get specific cluster info
kubectl cluster-info --context <CLUSTER_NAME>

# Further debug cluster info
kubectl cluster-info dump

# Change active k8s cluster
kubectl config use-context <CLUSTER_NAME>

# Get pod name first by checking all pods
kubectl get pods -A

# Get pods by label
kubectl get pods -n <NAMESPACE> -l <LABEL_NAME>=<LABEL_VALUE>

# Get all namespaces
kubectl get namespaces
kubectl get ns

# Redeploy a deployment
kubectl rollout restart deployment <DEPLOYMENT_NAME> -n <NAMESPACE>

################## Separation line ##################

# Check logs of particular pod for debugging
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Check job status
kubectl get jobs -n <NAMESPACE>

# Get job details
kubectl describe job <JOB_NAME> -n <NAMESPACE>

# Get logs from pods / containers in a pod (-c can be omitted if there is only one container in the pod)
kubectl logs <POD_NAME> -n <NAMESPACE> -c <CONTAINER_NAME>

################## MongoDB Specific Commands ##################

# Check MongoDB StatefulSet status
kubectl get statefulset mongodb
kubectl describe statefulset mongodb

# Check MongoDB pods and their status
kubectl get pods -l app=mongodb
kubectl describe pod mongodb-0

# Check MongoDB persistent volumes
kubectl get pv -l app=mongodb
kubectl get pvc -l app=mongodb

# Access MongoDB shell for debugging
kubectl exec -it mongodb-0 -- mongosh

# Check MongoDB logs
kubectl logs mongodb-0 -c mongodb

# Check MongoDB initialization logs
kubectl logs mongodb-0 -c mongodb-init-processor

# Test MongoDB connectivity from another pod
kubectl run mongodb-client --rm -it --image=mongo:7.0 -- mongosh mongodb://mongodb.default.svc.cluster.local:27017

# Check MongoDB services
kubectl get svc -l app=mongodb
kubectl describe svc mongodb
```
### Useful links
- [Kubetectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes Service Account](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Kubernetes ImagePullSecrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [Krew, k8s plugin manager](https://krew.sigs.k8s.io/docs/user-guide/setup/install/)
- [Kind network explanation](https://www.hwchiu.com/docs/2023/kind-network/)

## Troubleshooting

1. kube-proxy fails to start with error `E0830 03:46:39.257275 1 run.go:72] "command failed" err="failed complete: too many open files"`.


    The file descriptor limit (default 1024) is too low for a large number of pods, resulting in `too many open files` error. According to [official documentations](https://kind.sigs.k8s.io/docs/user/known-issues#pod-errors-due-to-too-many-open-files), adding inotify limit to `/etc/sysctl.conf` can completely resolve the issue, run `sysctl -p` to apply the changes.

2. kind cluster fails to start after host machine restart.

    The docker containers for the kind cluster are not automatically started after host machine restart. Run `docker start $(docker ps -a --filter "label=io.x-k8s.kind.cluster=<CLUSTER_NAME>" --format "{{.Names}}")` to start all kind containers. Then run `kubectl get nodes` to check if the cluster is up. If not, try to delete and recreate the cluster.

3. MongoDB StatefulSet fails to start or pods are in CrashLoopBackOff.

    **Check MongoDB secret**: Ensure the MongoDB secret exists and contains the correct keys:
    ```bash
    kubectl get secret mongodb-secret
    kubectl describe secret mongodb-secret
    ```

    **Check persistent volumes**: Ensure storage components are properly configured:
    ```bash
    kubectl get pv -l app=mongodb
    kubectl get pvc -l app=mongodb
    kubectl describe pvc mongodb-data-mongodb-0
    ```

    **Check initialization logs**: Look for errors in the init container:
    ```bash
    kubectl logs mongodb-0 -c mongodb-init-processor
    kubectl logs mongodb-0 -c mongodb
    ```

4. MongoDB connection issues from application pods.

    **Check MongoDB service**: Ensure the MongoDB service is running and accessible:
    ```bash
    kubectl get svc mongodb
    kubectl describe svc mongodb
    ```

    **Test connectivity**: Use a test pod to verify MongoDB connectivity:
    ```bash
    kubectl run mongodb-test --rm -it --image=mongo:7.0 -- mongosh mongodb://mongodb.default.svc.cluster.local:27017
    ```

    **Check DNS resolution**: Verify service DNS is working:
    ```bash
    kubectl run dns-test --rm -it --image=busybox -- nslookup mongodb.default.svc.cluster.local
    ```

5. MongoDB secret creation issues.

    **Use the dedicated script**: For secure secret creation:
    ```bash
    ./create-mongodb-secret.sh
    ```

    **Manual secret creation**: If the script fails:
    ```bash
    kubectl create secret generic mongodb-secret \
      --from-literal=MONGODB_APP_USER=root \
      --from-literal=MONGODB_APP_PASSWORD=your-secure-password
    ```