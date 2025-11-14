#!/bin/bash

# =============================================
# FluxCD Installation and Bootstrap Script
# Works on Ubuntu control plane nodes with containerd
# =============================================

set -e

# -------------------- Colors --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------- Configuration ----------------
FLUX_NAMESPACE="flux-system"
FLUX_PATH="./infrastructure/fluxcd/flux-system"
GITHUB_OWNER="Duggireddy-NSF"
GITHUB_REPOSITORY="devops-gitops"

# ----------------- Functions ------------------
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[STEP]${NC} $1"; }

# -------- Check Dependencies ------------------
check_dependencies() {
    print_header "Checking dependencies..."
    for cmd in kubectl curl; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed or not in PATH"
            exit 1
        fi
    done

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    print_status "Dependencies check passed"
}

# -------- Install FluxCD CLI ------------------
install_flux_cli() {
    print_header "Installing FluxCD CLI..."

    if command -v flux &> /dev/null; then
        local current_version
        current_version=$(flux version --client -o json | grep -o '"fluxVersion":"[^"]*' | sed 's/"fluxVersion":"//')
        print_status "FluxCD CLI already installed (version: $current_version)"
        read -p "Do you want to reinstall FluxCD CLI? (y/N): " -r
        [[ $REPLY =~ ^[Yy]$ ]] || return 0
    fi

    print_status "Installing FluxCD CLI using official script..."
    curl -s https://fluxcd.io/install.sh | sudo bash

    if flux version --client &> /dev/null; then
        local installed_version
        installed_version=$(flux version --client -o json | grep -o '"fluxVersion":"[^"]*' | sed 's/"fluxVersion":"//')
        print_status "FluxCD CLI successfully installed (version: $installed_version)"
    else
        print_error "FluxCD CLI installation failed"
        exit 1
    fi
}

# -------- Validate GitHub Credentials ------------
validate_github_credentials() {
    print_header "Validating GitHub credentials..."

    if [[ -z "$GITHUB_TOKEN" ]]; then
        print_error "GITHUB_TOKEN is not set"
        echo "Please create a GitHub Personal Access Token with:"
        echo "- repo (full control)"
        echo "- write:packages"
        echo "- read:packages"
        exit 1
    fi

    if [[ -z "$GITHUB_USER" ]]; then
        print_warning "GITHUB_USER not set, using GITHUB_OWNER: $GITHUB_OWNER"
        export GITHUB_USER="$GITHUB_OWNER"
    fi

    if ! curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user &> /dev/null; then
        print_error "GitHub authentication failed"
        exit 1
    fi

    print_status "GitHub credentials validated"
}

# -------- FluxCD Precheck -----------------------
run_precheck() {
    print_header "Running FluxCD pre-flight checks..."
    flux check --pre || { print_error "Pre-flight checks failed"; exit 1; }
    print_status "Pre-flight checks passed"
}

# -------- Bootstrap FluxCD ----------------------
bootstrap_flux() {
    print_header "Bootstrapping FluxCD..."
    print_status "Owner: $GITHUB_OWNER"
    print_status "Repository: $GITHUB_REPOSITORY"
    print_status "Path: $FLUX_PATH"
    print_status "Namespace: $FLUX_NAMESPACE"

    if kubectl get namespace "$FLUX_NAMESPACE" &> /dev/null; then
        print_warning "Namespace $FLUX_NAMESPACE already exists"
    fi

    flux bootstrap github \
        --owner="$GITHUB_OWNER" \
        --repository="$GITHUB_REPOSITORY" \
        --branch=main \
        --path="$FLUX_PATH" \
        --personal \
        --token-auth || { print_error "FluxCD bootstrap failed"; exit 1; }

    print_status "FluxCD bootstrap completed successfully"
}

# -------- Verify Installation ------------------
verify_installation() {
    print_header "Verifying FluxCD installation..."
    local controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")

    for ctrl in "${controllers[@]}"; do
        print_status "Waiting for $ctrl..."
        kubectl wait --for=condition=ready pod -l app="$ctrl" -n "$FLUX_NAMESPACE" --timeout=300s || \
            { print_error "$ctrl failed to become ready"; exit 1; }
    done

    flux check || { print_error "FluxCD health check failed"; exit 1; }
    print_status "FluxCD is healthy and ready"
    flux get all
}

# -------- Apply Initial Configs ----------------
apply_initial_configs() {
    print_header "Applying initial GitOps configurations..."

    [[ -f "infrastructure/fluxcd/namespaces/gitops-poc.yaml" ]] && \
        kubectl apply -f infrastructure/fluxcd/namespaces/gitops-poc.yaml

    [[ -d "infrastructure/fluxcd/sources" ]] && \
        kubectl apply -f infrastructure/fluxcd/sources/

    [[ -d "infrastructure/fluxcd/releases" ]] && \
        kubectl apply -k infrastructure/fluxcd/releases/

    print_status "Initial configurations applied"
}

# -------- Show Next Steps ---------------------
show_next_steps() {
    print_header "Installation Complete!"
    echo "Next steps:"
    echo "1. Set GitHub credentials for FluxCD:"
    echo "   export GITHUB_USERNAME=your-username"
    echo "   export GITHUB_TOKEN=your-token"
    echo "   ./scripts/setup/create-github-packages-secret.sh"
    echo "2. Monitor FluxCD reconciliation:"
    echo "   flux get sources git"
    echo "   flux get helmreleases"
    echo "   kubectl get pods -n gitops-poc"
    echo "3. View FluxCD logs if needed:"
    echo "   flux logs --follow --tail=10"
}

# -------- Main Function -----------------------
main() {
    echo "FluxCD Installation and Bootstrap Script"
    echo "======================================="
    check_dependencies
    validate_github_credentials
    install_flux_cli
    run_precheck
    bootstrap_flux
    verify_installation
    apply_initial_configs
    show_next_steps
}

# -------- Run Script --------------------------
main "$@"
