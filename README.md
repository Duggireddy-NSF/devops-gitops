# DevOps GitOps Repository

This repository contains the centralized GitOps configurations and infrastructure templates for deploying Spring Boot microservices using FluxCD and GitHub Packages.

## 🏗️ Architecture Overview

This GitOps setup implements a multi-tenant pattern designed to scale from a 2-service POC to enterprise-grade deployments, leveraging:

- **FluxCD** for GitOps continuous deployment
- **GitHub Container Registry** (ghcr.io) for container images
- **GitHub Packages** for unified artifact management
- **Kubernetes** with namespace-based isolation
- **Helm** for templated deployments

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

## 📁 Repository Structure

```
devops-gitops/
├── infrastructure/
│   ├── fluxcd/                     # FluxCD configurations
│   │   ├── flux-system/           # FluxCD installation manifests
│   │   ├── sources/               # Git repository sources
│   │   ├── releases/              # HelmRelease definitions
│   │   ├── namespaces/            # Namespace definitions
│   │   ├── secrets/               # GitHub Packages secrets
│   │   └── rbac/                  # Role-based access control
│   └── helm-templates/
│       ├── spring-boot-base/      # Base Helm chart for Spring Boot
│       └── common/                # Shared templates and utilities
├── scripts/
│   ├── setup/                     # Installation and setup scripts
│   ├── team-onboarding/           # Team onboarding automation
│   └── utilities/                 # Utility scripts
├── docs/                          # Documentation
├── examples/                      # Example configurations
└── tests/                         # Configuration validation tests
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (kubeadm or managed)
- kubectl configured and connected
- GitHub Personal Access Token with:
  - `repo` (full control)
  - `packages:read`
  - `packages:write`

### 1. Install FluxCD

```bash
# Set your GitHub credentials
export GITHUB_TOKEN=your-github-token
export GITHUB_USERNAME=your-github-username

# Install and bootstrap FluxCD
./scripts/setup/install-flux.sh
```

### 2. Create GitHub Packages Secret

```bash
# Create the secret for pulling container images
./scripts/setup/create-github-packages-secret.sh
```

### 3. Apply GitOps Configurations

```bash
# Apply all FluxCD configurations
kubectl apply -f infrastructure/fluxcd/namespaces/
kubectl apply -f infrastructure/fluxcd/sources/
kubectl apply -k infrastructure/fluxcd/releases/
```

### 4. Monitor Deployments

```bash
# Check FluxCD status
flux get all

# Monitor application deployments
kubectl get pods -n gitops-poc

# View deployment logs
flux logs --follow --tail=10
```

## 🔧 Configuration

### Adding a New Team/Service

1. **Create Application Repository** (see [Team Onboarding Guide](docs/ONBOARDING.md))
2. **Configure FluxCD Source:**
   ```bash
   # Copy template and customize
   cp infrastructure/fluxcd/sources/team-a-source.yaml infrastructure/fluxcd/sources/team-b-source.yaml
   # Edit the file to point to your team's repository
   ```

3. **Configure HelmRelease:**
   ```bash
   # Copy template and customize
   cp infrastructure/fluxcd/releases/team-a-release.yaml infrastructure/fluxcd/releases/team-b-release.yaml
   # Update the file with team-specific configurations
   ```

4. **Apply Configurations:**
   ```bash
   kubectl apply -f infrastructure/fluxcd/sources/team-b-source.yaml
   kubectl apply -f infrastructure/fluxcd/releases/team-b-release.yaml
   ```

### GitHub Packages Integration

This setup uses GitHub Container Registry (`ghcr.io`) for storing Docker images:

- **Registry URL:** `ghcr.io`
- **Image Format:** `ghcr.io/duggireddy-nsf/service-name:tag`
- **Authentication:** GitHub Personal Access Token
- **Pull Secret:** `github-packages-secret`

## 📚 Documentation

- [**Architecture Design**](../GitOps-Pipeline-Architecture-Design-GitHub-Packages.md) - Complete architecture documentation
- [**Team Onboarding**](docs/ONBOARDING.md) - Guide for onboarding new teams
- [**GitHub Packages Setup**](docs/GITHUB-PACKAGES.md) - Detailed GitHub Packages configuration
- [**Troubleshooting**](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [**Scaling Guide**](docs/SCALING.md) - Multi-tenant scaling strategies

## 🛠️ Scripts

### Setup Scripts

- `scripts/setup/install-flux.sh` - Install and bootstrap FluxCD
- `scripts/setup/create-github-packages-secret.sh` - Create GitHub Packages authentication

### Team Onboarding

- `scripts/team-onboarding/create-team-repo.sh` - Scaffold new team repository
- `scripts/team-onboarding/setup-team-access.sh` - Configure team RBAC

### Utilities

- `scripts/utilities/sync-status.sh` - Check FluxCD synchronization status
- `scripts/utilities/github-packages-cleanup.sh` - Clean up old packages

## 🔍 Monitoring

### FluxCD Status

```bash
# Check all FluxCD resources
flux get all

# Check specific resources
flux get sources git
flux get helmreleases
flux get kustomizations

# View reconciliation logs
flux logs --follow --tail=50
```

### Application Status

```bash
# Check pod status
kubectl get pods -n gitops-poc

# Check service status
kubectl get services -n gitops-poc

# View application logs
kubectl logs -l app.kubernetes.io/name=team-a-service -n gitops-poc
```

### GitHub Packages

```bash
# List packages in organization
gh api orgs/duggireddy-nsf/packages

# Check package details
gh api orgs/duggireddy-nsf/packages/container/team-a-service
```

## 🔒 Security

### Image Security

- All container images are scanned with Trivy during CI/CD
- Images are stored in private GitHub Container Registry
- Pull secrets are managed centrally
- Security contexts enforce non-root execution

### Access Control

- Namespace-based isolation
- RBAC policies for team separation
- GitHub organization-level package access control
- Kubernetes service account restrictions

## 🚨 Troubleshooting

### Common Issues

1. **Image Pull Errors**
   ```bash
   # Check secret exists
   kubectl get secret github-packages-secret -n gitops-poc
   
   # Recreate secret if needed
   ./scripts/setup/create-github-packages-secret.sh
   ```

2. **FluxCD Reconciliation Issues**
   ```bash
   # Check FluxCD status
   flux check
   
   # View controller logs
   flux logs --level=error
   
   # Force reconciliation
   flux reconcile source git team-a-service
   ```

3. **GitHub Authentication Problems**
   ```bash
   # Test GitHub token
   curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
   
   # Check token permissions
   gh auth status
   ```

See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for detailed solutions.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and test thoroughly
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push to branch: `git push origin feature/amazing-feature`
6. Create Pull Request

## 📄 License

This project is part of the GitOps POC and is intended for demonstration and internal use.

## 👥 Team

**DevOps Team** - Infrastructure and Platform Engineering

For questions or support, please contact the DevOps team or create an issue in this repository.

---

**Status:** ✅ Active Development  
**Version:** 1.0.0  
**Last Updated:** November 12, 2025  
**Maintained by:** DevOps Team
