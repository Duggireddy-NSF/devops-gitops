# DevOps GitOps FluxCD Setup Guide

## 🎯 Overview

This comprehensive guide walks through setting up a complete GitOps pipeline using FluxCD, Kubernetes, and GitHub Container Registry. The setup implements a multi-tenant architecture designed to scale from a proof-of-concept to enterprise-grade deployments.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Organization                           │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│  │ Team-A Repo │    │ Team-B Repo │    │ DevOps Repo │        │
│  │             │    │             │    │ (This Repo) │        │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │
│         │                  │                  │               │
│         ▼                  ▼                  ▼               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              GitHub Container Registry                  │   │
│  │                    (ghcr.io)                          │   │
│  └─────────────────────┬───────────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
            ┌─────────────────────────────────┐
            │      Kubernetes Cluster         │
            │                                 │
            │  ┌─────────────┐ ┌─────────────┐│
            │  │   Team-A    │ │   Team-B    ││
            │  │  Service    │ │  Service    ││
            │  └─────────────┘ └─────────────┘│
            │                                 │
            │       FluxCD Controllers        │
            └─────────────────────────────────┘
```

## 📋 Prerequisites & Environment Setup

### 🔧 Required Tools

Before starting, ensure you have the following tools installed:

#### 1. **Kubernetes Tools**
```bash
# kubectl - Kubernetes CLI
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

#### 2. **Container Tools**
```bash
# Docker (for testing image pulls)
sudo apt-get update
sudo apt-get install docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
sudo usermod -aG docker $USER
```

#### 3. **Utility Tools**
```bash
# Required utilities
sudo apt-get install curl wget git base64 jq
```

### 🔑 GitHub Setup

#### 1. **Personal Access Token (PAT)**
Create a GitHub Personal Access Token with the following permissions:

- **Repository Access:**
  - `repo` (Full control of private repositories)
  - `public_repo` (Access public repositories)

- **Package Access:**
  - `read:packages` (Download packages from GitHub Package Registry)
  - `write:packages` (Upload packages to GitHub Package Registry)
  - `delete:packages` (Delete packages from GitHub Package Registry)

#### 2. **Environment Variables**
```bash
# Set your GitHub credentials
export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
export GITHUB_OWNER="Duggireddy-NSF"  # Your organization name

# Add to ~/.bashrc or ~/.zshrc for persistence
echo 'export GITHUB_USERNAME="your-github-username"' >> ~/.bashrc
echo 'export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"' >> ~/.bashrc
echo 'export GITHUB_OWNER="Duggireddy-NSF"' >> ~/.bashrc
```

#### 3. **Verify GitHub Authentication**
```bash
# Test GitHub API access
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Test GitHub Container Registry access
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin
```

### ⚙️ Kubernetes Cluster Setup

#### Option 1: Local Development (kubeadm/minikube)
```bash
# For minikube
minikube start --memory=4096 --cpus=2

# For kind (Kubernetes in Docker)
kind create cluster --name gitops-cluster
```

#### Option 2: Cloud Provider (AWS EKS Example)
```bash
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Create EKS cluster
eksctl create cluster --name gitops-cluster --region us-west-2 --nodes 3
```

#### Verify Cluster Access
```bash
# Check cluster connection
kubectl cluster-info

# Check nodes
kubectl get nodes

# Check available resources
kubectl top nodes  # Requires metrics-server
```

## 🚀 Step-by-Step Installation Guide

### Step 1: FluxCD CLI Installation

#### Automated Installation (Recommended)
```bash
# Navigate to project directory
cd devops-gitops

# Run the automated installation script
chmod +x scripts/setup/install-flux.sh
./scripts/setup/install-flux.sh
```

#### Manual Installation
```bash
# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')

# Download FluxCD CLI
curl -sL "https://github.com/fluxcd/flux2/releases/latest/download/flux_${OS}_${ARCH}.tar.gz" | tar xz

# Move to PATH
sudo mv flux /usr/local/bin/

# Verify installation
flux version --client
```

### Step 2: FluxCD Bootstrap Process

#### Understanding the Bootstrap Process

The bootstrap process:
1. **Installs FluxCD components** in your cluster
2. **Creates a GitRepository** pointing to your devops-gitops repo
3. **Sets up continuous reconciliation** from your Git repository
4. **Configures GitHub authentication** for private repositories

#### Run Bootstrap
```bash
# Ensure environment variables are set
echo "GitHub Owner: $GITHUB_OWNER"
echo "GitHub Username: $GITHUB_USERNAME"
echo "Token set: $(if [ -n "$GITHUB_TOKEN" ]; then echo "Yes"; else echo "No"; fi)"

# Run pre-flight checks
flux check --pre

# Bootstrap FluxCD
flux bootstrap github \
  --owner=$GITHUB_OWNER \
  --repository=devops-gitops \
  --branch=main \
  --path=./infrastructure/fluxcd/flux-system \
  --personal \
  --token-auth
```

#### What Happens During Bootstrap:
1. **FluxCD Controllers Installation:**
   - `source-controller`: Manages Git repositories and Helm repositories
   - `kustomize-controller`: Applies Kustomize configurations
   - `helm-controller`: Manages Helm releases
   - `notification-controller`: Handles notifications and webhooks

2. **GitRepository Creation:**
   - Creates a GitRepository resource pointing to your devops-gitops repo
   - Sets up SSH key or token authentication
   - Configures sync interval (default: 1 minute)

3. **Kustomization Setup:**
   - Creates root Kustomization that applies FluxCD configurations
   - Enables recursive directory processing

#### Verify Bootstrap Success
```bash
# Check FluxCD installation
flux check

# View installed controllers
kubectl get pods -n flux-system

# Check FluxCD status
flux get all

# View GitRepository status
flux get sources git
```

### Step 3: GitHub Packages Authentication Setup

#### Why This Step is Critical

GitHub Container Registry (ghcr.io) requires authentication to pull private container images. This step creates the necessary Kubernetes secrets.

#### Automated Secret Creation
```bash
# Navigate to project directory
cd devops-gitops

# Run the secret creation script
chmod +x scripts/setup/create-github-packages-secret.sh
./scripts/setup/create-github-packages-secret.sh
```

#### Manual Secret Creation
```bash
# Create the gitops-poc namespace
kubectl create namespace gitops-poc

# Create Docker registry secret
kubectl create secret docker-registry github-packages-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_TOKEN \
  --namespace=gitops-poc

# Add labels for better organization
kubectl label secret github-packages-secret \
  app.kubernetes.io/name=github-packages-secret \
  app.kubernetes.io/part-of=gitops-poc \
  --namespace=gitops-poc
```

#### Verify Secret Creation
```bash
# Check if secret exists
kubectl get secrets -n gitops-poc

# Describe the secret (without showing sensitive data)
kubectl describe secret github-packages-secret -n gitops-poc

# Test image pull capability
kubectl run test-pull --image=ghcr.io/duggireddy-nsf/team-a-service:latest \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"github-packages-secret"}]}}' \
  --namespace=gitops-poc --rm -it --restart=Never -- echo "Image pull successful"
```

### Step 4: GitOps Configuration Application

#### Understanding the Configuration Structure

```
infrastructure/fluxcd/
├── namespaces/           # Kubernetes namespaces
│   └── gitops-poc.yaml  # Application namespace
├── sources/             # Git repository sources
│   └── team-a-source.yaml
├── releases/            # Helm releases
│   ├── kustomization.yaml
│   └── team-a-release.yaml
└── secrets/             # Authentication secrets
    └── github-packages-secret.yaml
```

#### Apply Configurations Step by Step

##### 1. Apply Namespaces
```bash
# Create application namespaces
kubectl apply -f infrastructure/fluxcd/namespaces/

# Verify namespace creation
kubectl get namespaces
kubectl describe namespace gitops-poc
```

##### 2. Apply Git Sources
```bash
# Apply GitRepository sources
kubectl apply -f infrastructure/fluxcd/sources/

# Check source status
flux get sources git

# View detailed source information
kubectl describe gitrepository team-a-service -n flux-system
```

##### 3. Apply Helm Releases
```bash
# Apply HelmRelease configurations
kubectl apply -k infrastructure/fluxcd/releases/

# Monitor release status
flux get helmreleases

# Watch deployment progress
kubectl get pods -n gitops-poc -w
```

### Step 5: Verification and Testing

#### FluxCD System Verification
```bash
# Overall FluxCD health check
flux check

# Check all FluxCD resources
flux get all

# View FluxCD controller logs
flux logs --follow --tail=50
```

#### Application Deployment Verification
```bash
# Check pod status
kubectl get pods -n gitops-poc

# Check services
kubectl get services -n gitops-poc

# Check ingress (if configured)
kubectl get ingress -n gitops-poc

# View application logs
kubectl logs -l app.kubernetes.io/name=team-a-service -n gitops-poc
```

#### End-to-End Testing
```bash
# Port forward to test application
kubectl port-forward service/team-a-service 8080:80 -n gitops-poc

# Test application endpoint (in another terminal)
curl http://localhost:8080/actuator/health

# Test application functionality
curl http://localhost:8080/api/hello
```

## 🔧 Configuration Deep Dive

### GitRepository Source Configuration

**File:** `infrastructure/fluxcd/sources/team-a-source.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: team-a-service
  namespace: flux-system
spec:
  interval: 1m0s              # Sync frequency
  ref:
    branch: main              # Branch to monitor
  url: https://github.com/Duggireddy-NSF/team-a-service.git
  ignore: |                   # Files to ignore for performance
    *.md
    .github/
    src/
    target/
    .mvn/
    *.log
```

**Key Configuration Options:**

- **`interval`**: How often FluxCD checks for changes (1m = every minute)
- **`ref.branch`**: Git branch to monitor (can also be tag or commit)
- **`ignore`**: Glob patterns to ignore during sync for better performance
- **`secretRef`**: Reference to authentication secret (for private repos)

### HelmRelease Configuration

**File:** `infrastructure/fluxcd/releases/team-a-release.yaml`

#### Core Release Configuration
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: team-a-service
  namespace: flux-system
spec:
  interval: 10m                    # Reconciliation frequency
  targetNamespace: gitops-poc      # Deployment namespace
  chart:
    spec:
      chart: ./helm               # Path to Helm chart
      version: '*'                # Chart version (latest)
      sourceRef:
        kind: GitRepository
        name: team-a-service      # Reference to GitRepository
```

#### Image Configuration
```yaml
values:
  image:
    registry: ghcr.io
    repository: duggireddy-nsf/team-a-service
    pullPolicy: IfNotPresent
  
  imagePullSecrets:
    - name: github-packages-secret  # Authentication for private images
```

#### Security Configuration
```yaml
  # Pod-level security
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
    fsGroup: 1001
  
  # Container-level security
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
    readOnlyRootFilesystem: false
```

#### Health Checks
```yaml
  health:
    livenessProbe:
      httpGet:
        path: /actuator/health/liveness
        port: http
      initialDelaySeconds: 60
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    readinessProbe:
      httpGet:
        path: /actuator/health/readiness
        port: http
      initialDelaySeconds: 30
      periodSeconds: 10
```

#### Resource Management
```yaml
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi
```

#### Failure Handling
```yaml
  install:
    createNamespace: true
    remediation:
      retries: 3
  
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  
  rollback:
    cleanupOnFail: true
    force: false
```

### GitHub Packages Secret Configuration

**File:** `infrastructure/fluxcd/secrets/github-packages-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-packages-secret
  namespace: gitops-poc
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: |
    # Base64 encoded Docker config JSON
    # Format: {"auths":{"ghcr.io":{"username":"USER","password":"TOKEN"}}}
```

**Associated Service Account:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-packages-sa
  namespace: gitops-poc
imagePullSecrets:
  - name: github-packages-secret
```

## 👥 Team Onboarding Process

### Adding a New Team/Service

#### Step 1: Create Team Repository

1. **Repository Structure** (for new team):
```
team-b-service/
├── Dockerfile
├── pom.xml (or package.json, etc.)
├── helm/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── .github/
│   └── workflows/
│       └── ci-cd.yml
└── src/
    └── (application source code)
```

2. **Required GitHub Actions Workflow** (`.github/workflows/ci-cd.yml`):
```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up JDK 11
      uses: actions/setup-java@v4
      with:
        java-version: '11'
        distribution: 'temurin'
    
    - name: Build with Maven
      run: mvn clean package
    
    - name: Log in to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: |
          ghcr.io/${{ github.repository_owner }}/team-b-service:latest
          ghcr.io/${{ github.repository_owner }}/team-b-service:${{ github.sha }}
```

#### Step 2: Configure FluxCD Source

**File:** `infrastructure/fluxcd/sources/team-b-source.yaml`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: team-b-service
  namespace: flux-system
  labels:
    app.kubernetes.io/name: team-b-service-source
    app.kubernetes.io/part-of: gitops-poc
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/Duggireddy-NSF/team-b-service.git
  ignore: |
    *.md
    .github/
    src/
    target/
    .mvn/
    *.log
```

#### Step 3: Configure HelmRelease

**File:** `infrastructure/fluxcd/releases/team-b-release.yaml`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: team-b-service
  namespace: flux-system
  labels:
    app.kubernetes.io/name: team-b-service-release
    app.kubernetes.io/part-of: gitops-poc
spec:
  interval: 10m
  targetNamespace: gitops-poc
  chart:
    spec:
      chart: ./helm
      version: '*'
      sourceRef:
        kind: GitRepository
        name: team-b-service
        namespace: flux-system
  values:
    app:
      name: team-b-service
      version: "1.0.0"
    
    image:
      registry: ghcr.io
      repository: duggireddy-nsf/team-b-service
      pullPolicy: IfNotPresent
    
    imagePullSecrets:
      - name: github-packages-secret
    
    service:
      type: ClusterIP
      port: 80
      targetPort: 8080
    
    ingress:
      enabled: true
      className: "nginx"
      hosts:
        - host: team-b-service.local
          paths:
            - path: /
              pathType: Prefix
```

#### Step 4: Apply New Team Configuration

```bash
# Apply the new source
kubectl apply -f infrastructure/fluxcd/sources/team-b-source.yaml

# Apply the new release
kubectl apply -f infrastructure/fluxcd/releases/team-b-release.yaml

# Monitor the deployment
flux get all
kubectl get pods -n gitops-poc -w
```

#### Step 5: Update Kustomization (if needed)

**File:** `infrastructure/fluxcd/releases/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - team-a-release.yaml
  - team-b-release.yaml  # Add new team
```

### Team Onboarding Automation Script

**File:** `scripts/team-onboarding/onboard-team.sh`

```bash
#!/bin/bash

TEAM_NAME="$1"
REPO_URL="$2"

if [[ -z "$TEAM_NAME" || -z "$REPO_URL" ]]; then
    echo "Usage: $0 <team-name> <repo-url>"
    exit 1
fi

# Create source configuration
cat > "infrastructure/fluxcd/sources/${TEAM_NAME}-source.yaml" <<EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: ${TEAM_NAME}
  namespace: flux-system
  labels:
    app.kubernetes.io/name: ${TEAM_NAME}-source
    app.kubernetes.io/part-of: gitops-poc
spec:
  interval: 1m0s
  ref:
    branch: main
  url: ${REPO_URL}
  ignore: |
    *.md
    .github/
    src/
    target/
    .mvn/
    *.log
EOF

# Create release configuration
cat > "infrastructure/fluxcd/releases/${TEAM_NAME}-release.yaml" <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ${TEAM_NAME}
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: gitops-poc
  chart:
    spec:
      chart: ./helm
      sourceRef:
        kind: GitRepository
        name: ${TEAM_NAME}
  values:
    image:
      registry: ghcr.io
      repository: duggireddy-nsf/${TEAM_NAME}
    imagePullSecrets:
      - name: github-packages-secret
EOF

# Apply configurations
kubectl apply -f "infrastructure/fluxcd/sources/${TEAM_NAME}-source.yaml"
kubectl apply -f "infrastructure/fluxcd/releases/${TEAM_NAME}-release.yaml"

echo "Team ${TEAM_NAME} onboarded successfully!"
```

## 🔍 Monitoring & Troubleshooting

### FluxCD Status Monitoring

#### Basic Status Commands
```bash
# Overall FluxCD health
flux check

# List all FluxCD resources
flux get all

# Check specific resource types
flux get sources git
flux get helmreleases
flux get kustomizations

# Check with detailed output
flux get sources git --output=yaml
```

#### Continuous Monitoring
```bash
# Watch all resources
watch flux get all

# Monitor specific namespace
watch kubectl get pods -n gitops-poc

# Follow FluxCD logs
flux logs --follow --tail=50

# Monitor specific controller
kubectl logs -f deployment/source-controller -n flux-system
```

### Troubleshooting Common Issues

#### 1. Image Pull Errors

**Symptoms:**
- Pods stuck in `ImagePullBackOff` state
- Events show authentication failures

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n gitops-poc

# Check image pull secret
kubectl get secret github-packages-secret -n gitops-poc
kubectl describe secret github-packages-secret -n gitops-poc

# Test image pull manually
kubectl run test-pull --image=ghcr.io/duggireddy-nsf/team-a-service:latest \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"github-packages-secret"}]}}' \
  --namespace=gitops-poc --rm -it --restart=Never -- echo "Success"
```

**Solutions:**
```bash
# Recreate the secret with correct credentials
./scripts/setup/create-github-packages-secret.sh

# Verify GitHub token permissions
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Check if image exists in registry
docker pull ghcr.io/duggireddy-nsf/team-a-service:latest
```

#### 2. FluxCD Reconciliation Issues

**Symptoms:**
- GitRepository shows `Failed` status
- HelmRelease stuck in pending state
- Resources not being updated

**Diagnosis:**
```bash
# Check GitRepository status
flux describe source git team-a-service

# Check HelmRelease status
flux describe helmrelease team-a-service

# View controller logs
flux logs --kind=GitRepository --name=team-a-service
flux logs --kind=HelmRelease --name=team-a-service
```

**Solutions:**
```bash
# Force reconciliation
flux reconcile source git team-a-service
flux reconcile helmrelease team-a-service

# Check GitHub authentication
kubectl get secret flux-system -n flux-system -o yaml

# Verify repository access
git clone https://github.com/Duggireddy-NSF/team-a-service.git /tmp/test-clone
```

#### 3. Helm Chart Issues

**Symptoms:**
- HelmRelease shows `Install Failed` or `Upgrade Failed`
- Application pods not starting correctly

**Diagnosis:**
```bash
# Check HelmRelease status
kubectl describe helmrelease team-a-service -n flux-system

# View Helm release status
helm list -n gitops-poc

# Check Helm release history
helm history team-a-service -n gitops-poc

# Debug Helm chart
kubectl get events -n gitops-poc --sort-by='.lastTimestamp'
```

**Solutions:**
```bash
# Manual Helm dry-run test
cd /path/to/team-a-service
helm template ./helm --namespace gitops-poc

# Lint Helm chart
helm lint ./helm

# Manual Helm install for testing
helm install team-a-service ./helm --namespace gitops-poc --dry-run --debug
```

#### 4. Network/Connectivity Issues

**Symptoms:**
- Services not accessible
- Ingress not working
- Inter-service communication failures

**Diagnosis:**
```bash
# Check service endpoints
kubectl get endpoints -n gitops-poc

# Check ingress status
kubectl describe ingress -n gitops-poc

# Test service connectivity
kubectl run debug --image=nicolaka/netshoot -it --rm --restart=Never -- /bin/bash
# Inside the container:
# nslookup team-a-service.gitops-poc.svc.cluster.local
# curl http://team-a-service.gitops-poc.svc.cluster.local
```

**Solutions:**
```bash
# Check network policies
kubectl get networkpolicies -n gitops-poc

# Verify ingress controller
kubectl get pods -n ingress-nginx  # or your ingress namespace

# Test port forwarding
kubectl port-forward service/team-a-service 8080:80 -n gitops-poc
```

### Log Analysis Techniques

#### FluxCD Controller Logs
```bash
# Source controller (Git operations)
kubectl logs deployment/source-controller -n flux-system | grep team-a-service

# Helm controller (Helm operations)
kubectl logs deployment/helm-controller -n flux-system | grep team-a-service

# Kustomize controller (Kustomize operations)
kubectl logs deployment/kustomize-controller -n flux-system

# Filter for errors
kubectl logs deployment/source-controller -n flux-system | grep -E "(error|Error|ERROR)"
```

#### Application Logs
```bash
# Application container logs
kubectl logs -l app.kubernetes.io/name=team-a-service -n gitops-poc

# Follow logs in real-time
kubectl logs -l app.kubernetes.io/name=team-a-service -n gitops-poc -f

# Previous container logs (if pod restarted)
kubectl logs -l app.kubernetes.io/name=team-a-service -n gitops-poc --previous

# Multiple containers in pod
kubectl logs pod-name -c container-name -n gitops-poc
```

#### Event Analysis
```bash
# Recent events in namespace
kubectl get events -n gitops-poc --sort-by='.lastTimestamp'

# Events for specific resource
kubectl describe pod team-a-service-xxx -n gitops-poc

# Watch events in real-time
kubectl get events -n gitops-poc --watch
```

### Performance Monitoring

#### Resource Usage
```bash
# Pod resource usage
kubectl top pods -n gitops-poc

# Node resource usage
kubectl top nodes

# Detailed resource information
kubectl describe node <node-name>
```

#### FluxCD Performance
```bash
# Controller resource usage
kubectl top pods -n flux-system

# Controller metrics (if Prometheus is available)
kubectl port-forward -n flux-system svc/source-controller 8080:80
curl http://localhost:8080/metrics | grep flux_
```

## 🔒 Security Best Practices

### Pod Security Standards

#### Security Context Configuration
```yaml
# In HelmRelease values
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 1001
  fsGroup: 1001
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
    - ALL
  runAsNonRoot: true
  runAsUser: 1001
```

#### Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: team-a-service-netpol
  namespace: gitops-poc
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: team-a-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

### RBAC Configuration

#### FluxCD Service Account Permissions
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-manager
  namespace: gitops-poc
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### Secret Management

#### Sealed Secrets Integration
```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Create sealed secret
echo -n mypassword | kubectl create secret generic mysecret --dry-run=client --from-file=password=/dev/stdin -o yaml | kubeseal -o yaml > mysealedsecret.yaml

# Apply sealed secret
kubectl apply -f mysealedsecret.yaml
```

### Image Security Scanning

#### Container Image Scanning with Trivy
```bash
# Scan image for vulnerabilities
trivy image ghcr.io/duggireddy-nsf/team-a-service:latest

# Scan with specific severity levels
trivy image --severity HIGH,CRITICAL ghcr.io/duggireddy-nsf/team-a-service:latest

# Generate report in JSON format
trivy image --format json --output report.json ghcr.io/duggireddy-nsf/team-a-service:latest
```

## 🚀 Advanced Topics

### Multi-Environment Setup

#### Environment-Specific Configuration

**Directory Structure:**
```
environments/
├── development/
│   ├── kustomization.yaml
│   └── patches/
├── staging/
│   ├── kustomization.yaml
│   └── patches/
└── production/
    ├── kustomization.yaml
    └── patches/
```

**Development Environment** (`environments/development/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../infrastructure/fluxcd/namespaces/
  - ../../infrastructure/fluxcd/sources/
  - ../../infrastructure/fluxcd/releases/

patches:
  - target:
      kind: HelmRelease
      name: team-a-service
    patch: |-
      - op: replace
        path: /spec/values/image/tag
        value: "develop"
      - op: replace
        path: /spec/values/resources/requests/memory
        value: "128Mi"
      - op: replace
        path: /spec/values/resources/limits/memory
        value: "256Mi"
```

**Production Environment** (`environments/production/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../infrastructure/fluxcd/namespaces/
  - ../../infrastructure/fluxcd/sources/
  - ../../infrastructure/fluxcd/releases/

patches:
  - target:
      kind: HelmRelease
      name: team-a-service
    patch: |-
      - op: replace
        path: /spec/values/replicaCount
        value: 3
      - op: replace
        path: /spec/values/autoscaling/enabled
        value: true
      - op: replace
        path: /spec/values/resources/requests/memory
        value: "512Mi"
      - op: replace
        path: /spec/values/resources/limits/memory
        value: "1Gi"
```

### Notifications and Alerting

#### Slack Integration
```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Provider
metadata:
  name: slack-bot
  namespace: flux-system
spec:
  type: slack
  channel: gitops-alerts
  secretRef:
    name: slack-webhook-secret

---
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Alert
metadata:
  name: gitops-alert
  namespace: flux-system
spec:
  providerRef:
    name: slack-bot
  eventSeverity: info
  eventSources:
    - kind: GitRepository
      name: '*'
    - kind: HelmRelease
      name: '*'
  summary: "FluxCD Event: {{ .InvolvedObject.kind }}/{{ .InvolvedObject.name }}"
```

#### Create Slack Webhook Secret
```bash
kubectl create secret generic slack-webhook-secret \
  --from-literal=address=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
  --namespace=flux-system
```

### Backup and Disaster Recovery

#### GitOps Repository Backup Strategy

1. **Automated Git Backups**:
   - Use GitHub's built-in backup features
   - Set up repository mirroring to secondary Git providers
   - Implement automated Git bundle creation

2. **Cluster State Backup**:
```bash
# Backup FluxCD configurations
kubectl get all -n flux-system -o yaml > flux-backup.yaml

# Backup application configurations
kubectl get all -n gitops-poc -o yaml > app-backup.yaml

# Use Velero for comprehensive cluster backups
velero backup create gitops-backup --include-namespaces flux-system,gitops-poc
```

3. **Recovery Procedures**:
```bash
# Restore FluxCD from backup
kubectl apply -f flux-backup.yaml

# Restore applications
kubectl apply -f app-backup.yaml

# Restore from Velero backup
velero restore create --from-backup gitops-backup
```

### Scaling Considerations

#### Horizontal Scaling

**Multi-Cluster Setup:**
```yaml
# cluster-1-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: cluster-1-config
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: cluster-1
  url: https://github.com/Duggireddy-NSF/devops-gitops.git

# cluster-2-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: cluster-2-config
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: cluster-2
  url: https://github.com/Duggireddy-NSF/devops-gitops.git
```

**Tenant Isolation:**
```yaml
# tenant-a-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    toolkit.fluxcd.io/tenant: tenant-a

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-reconciler
  namespace: tenant-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kustomize-controller
  namespace: flux-system
```

### Performance Optimization

#### FluxCD Controller Tuning
```yaml
# Increase reconciliation workers
apiVersion: apps/v1
kind: Deployment
metadata:
  name: source-controller
  namespace: flux-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --concurrent=10  # Increase from default 4
        - --requeue-dependency=30s
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 1Gi
```

#### Git Repository Optimization
```yaml
# Optimize GitRepository with shallow clones
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: optimized-source
spec:
  interval: 5m0s  # Reduce frequency for stable repos
  ref:
    branch: main
  url: https://github.com/Duggireddy-NSF/team-a-service.git
  ignore: |
    # Comprehensive ignore patterns
    *.md
    *.txt
    *.log
    .github/
    .git/
    src/
    target/
    build/
    node_modules/
    .idea/
    .vscode/
    **/*.test.*
    **/*.spec.*
```

## 🎓 Best Practices Summary

### Repository Structure Best Practices

1. **Separate Concerns**:
   - Keep infrastructure and application code in separate repositories
   - Use clear directory structures with logical grouping
   - Implement consistent naming conventions

2. **Version Management**:
   - Use semantic versioning for releases
   - Tag important milestones
   - Implement branch protection rules

3. **Security First**:
   - Never commit secrets in plain text
   - Use proper RBAC configurations
   - Implement least privilege principles
   - Regular security scanning

### GitOps Workflow Best Practices

1. **Pull Request Workflow**:
   - Require PR reviews for all changes
   - Implement automated testing in PRs
   - Use branch protection rules
   - Document changes with clear commit messages

2. **Deployment Strategy**:
   - Use blue-green or canary deployments
   - Implement proper health checks
   - Set up monitoring and alerting
   - Have rollback procedures ready

3. **Monitoring and Observability**:
   - Monitor GitOps pipeline health
   - Track deployment success rates
   - Set up proper logging
   - Implement performance monitoring

## 📚 Additional Resources

### Documentation Links
- [FluxCD Official Documentation](https://fluxcd.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [GitHub Container Registry Guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

### Community Resources
- [FluxCD Community](https://github.com/fluxcd/community)
- [CNCF GitOps Working Group](https://github.com/cncf/tag-app-delivery/tree/main/gitops-wg)
- [Awesome GitOps](https://github.com/weaveworks/awesome-gitops)

### Training and Certification
- [CNCF GitOps Certification](https://training.linuxfoundation.org/certification/certified-gitops-associate-cgoa/)
- [Kubernetes Certification Programs](https://www.cncf.io/certification/training/)

## 🤝 Contributing

### How to Contribute

1. **Fork the Repository**
2. **Create Feature Branch**: `git checkout -b feature/amazing-feature`
3. **Make Changes**: Follow coding standards and best practices
4. **Test Thoroughly**: Ensure all changes work as expected
5. **Commit Changes**: `git commit -m 'Add amazing feature'`
6. **Push to Branch**: `git push origin feature/amazing-feature`
7. **Create Pull Request**: Provide clear description of changes

### Development Guidelines

- Follow the existing code style and patterns
- Add documentation for new features
- Include tests where applicable
- Update this guide if adding new procedures
- Ensure backward compatibility

---

## 📄 Conclusion

This comprehensive setup guide provides everything needed to implement a production-ready GitOps pipeline using FluxCD. The architecture is designed to be scalable, secure, and maintainable, supporting growth from a simple POC to enterprise-scale deployments.

### Quick Reference Commands

```bash
# Health Check
flux check

# Status Overview
flux get all

# Force Sync
flux reconcile source git team-a-service

# View Logs
flux logs --follow --tail=50

# Emergency Stop
kubectl patch helmrelease team-a-service -n flux-system -p '{"spec":{"suspend":true}}' --type=merge
```

### Support and Troubleshooting

For issues not covered in this guide:

1. Check the [troubleshooting section](#monitoring--troubleshooting) above
2. Review FluxCD controller logs
3. Consult the official FluxCD documentation
4. Engage with the community through GitHub discussions
5. Contact the DevOps team for internal support

---

**Status**: ✅ Production Ready  
**Version**: 2.0.0  
**Last Updated**: November 13, 2025  
**Maintained by**: DevOps Team

*This guide is a living document. Please keep it updated as the infrastructure evolves.*
