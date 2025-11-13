#!/bin/bash

# FluxCD Installation and Bootstrap Script
# This script installs FluxCD CLI and bootstraps FluxCD in a Kubernetes cluster with GitHub integration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FLUX_VERSION="latest"
GITHUB_OWNER="Duggireddy-NSF"
GITHUB_REPOSITORY="devops-gitops"
FLUX_NAMESPACE="flux-system"
FLUX_PATH="./infrastructure/fluxcd/flux-system"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if required tools are available
check_dependencies() {
    print_header "Checking dependencies..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_error "Please ensure kubectl is configured and cluster is accessible"
        exit 1
    fi
    
    print_status "Dependencies check passed"
}

# Function to install FluxCD CLI
install_flux_cli() {
    print_header "Installing FluxCD CLI..."
    
    if command -v flux &> /dev/null; then
        local current_version=$(flux version --client -o json | grep -o '"fluxVersion":"[^"]*' | sed 's/"fluxVersion":"//')
        print_status "FluxCD CLI already installed (version: $current_version)"
        
        read -p "Do you want to reinstall FluxCD CLI? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Detect OS and architecture
    local os=""
    local arch=""
    
    case "$(uname -s)" in
        Linux*)     os="linux";;
        Darwin*)    os="darwin";;
        CYGWIN*|MINGW*|MSYS*) os="windows";;
        *)          print_error "Unsupported OS: $(uname -s)"; exit 1;;
    esac
    
    case "$(uname -m)" in
        x86_64)     arch="amd64";;
        arm64)      arch="arm64";;
        aarch64)    arch="arm64";;
        *)          print_error "Unsupported architecture: $(uname -m)"; exit 1;;
    esac
    
    # Download and install FluxCD CLI
    local flux_url="https://github.com/fluxcd/flux2/releases/latest/download/flux_${os}_${arch}.tar.gz"
    local temp_dir=$(mktemp -d)
    
    print_status "Downloading FluxCD CLI from $flux_url"
    curl -sL "$flux_url" | tar xz -C "$temp_dir"
    
    # Move to /usr/local/bin or ask user for installation path
    if [[ -w "/usr/local/bin" ]]; then
        sudo mv "$temp_dir/flux" /usr/local/bin/flux
        sudo chmod +x /usr/local/bin/flux
        print_status "FluxCD CLI installed to /usr/local/bin/flux"
    else
        print_warning "Cannot write to /usr/local/bin"
        echo "Please move $temp_dir/flux to a directory in your PATH manually"
        echo "For example: sudo mv $temp_dir/flux /usr/local/bin/flux"
        exit 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    # Verify installation
    if flux version --client &> /dev/null; then
        local installed_version=$(flux version --client -o json | grep -o '"fluxVersion":"[^"]*' | sed 's/"fluxVersion":"//')
        print_status "FluxCD CLI successfully installed (version: $installed_version)"
    else
        print_error "FluxCD CLI installation failed"
        exit 1
    fi
}

# Function to validate GitHub credentials
validate_github_credentials() {
    print_header "Validating GitHub credentials..."
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        print_error "GITHUB_TOKEN environment variable is not set"
        echo "Please create a Personal Access Token with the following permissions:"
        echo "- repo (full control)"
        echo "- write:packages"
        echo "- read:packages"
        echo ""
        echo "Then set it using: export GITHUB_TOKEN=your-token"
        exit 1
    fi
    
    if [[ -z "$GITHUB_USER" ]]; then
        print_warning "GITHUB_USER not set, using GITHUB_OWNER: $GITHUB_OWNER"
        export GITHUB_USER="$GITHUB_OWNER"
    fi
    
    # Test GitHub authentication
    if ! curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user &>/dev/null; then
        print_error "GitHub authentication failed"
        print_error "Please check your GITHUB_TOKEN"
        exit 1
    fi
    
    print_status "GitHub credentials validated"
}

# Function to run FluxCD pre-flight checks
run_precheck() {
    print_header "Running FluxCD pre-flight checks..."
    
    if flux check --pre; then
        print_status "Pre-flight checks passed"
    else
        print_error "Pre-flight checks failed"
        print_error "Please resolve the issues above before continuing"
        exit 1
    fi
}

# Function to bootstrap FluxCD
bootstrap_flux() {
    print_header "Bootstrapping FluxCD..."
    
    local owner="${1:-$GITHUB_OWNER}"
    local repository="${2:-$GITHUB_REPOSITORY}"
    local path="${3:-$FLUX_PATH}"
    
    print_status "Bootstrapping FluxCD with:"
    echo "  - Owner: $owner"
    echo "  - Repository: $repository"
    echo "  - Path: $path"
    echo "  - Namespace: $FLUX_NAMESPACE"
    
    # Check if FluxCD is already installed
    if kubectl get namespace "$FLUX_NAMESPACE" &>/dev/null; then
        print_warning "FluxCD namespace '$FLUX_NAMESPACE' already exists"
        
        if kubectl get deployment source-controller -n "$FLUX_NAMESPACE" &>/dev/null; then
            print_warning "FluxCD appears to be already installed"
            read -p "Do you want to continue with bootstrap (this will update existing installation)? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Skipping FluxCD bootstrap"
                return 0
            fi
        fi
    fi
    
    # Bootstrap FluxCD
    if flux bootstrap github \
        --owner="$owner" \
        --repository="$repository" \
        --branch=main \
        --path="$path" \
        --personal \
        --token-auth; then
        print_status "FluxCD bootstrap completed successfully"
    else
        print_error "FluxCD bootstrap failed"
        exit 1
    fi
}

# Function to verify FluxCD installation
verify_installation() {
    print_header "Verifying FluxCD installation..."
    
    # Wait for FluxCD controllers to be ready
    print_status "Waiting for FluxCD controllers to be ready..."
    
    local controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
    
    for controller in "${controllers[@]}"; do
        print_status "Waiting for $controller..."
        if kubectl wait --for=condition=ready pod -l app="$controller" -n "$FLUX_NAMESPACE" --timeout=300s; then
            print_status "$controller is ready"
        else
            print_error "$controller failed to become ready"
            return 1
        fi
    done
    
    # Run FluxCD health check
    if flux check; then
        print_status "FluxCD is healthy and ready"
    else
        print_error "FluxCD health check failed"
        return 1
    fi
    
    # Show FluxCD status
    echo ""
    print_status "FluxCD Status:"
    flux get all
}

# Function to apply initial configurations
apply_initial_configs() {
    print_header "Applying initial GitOps configurations..."
    
    # Apply namespaces
    if [[ -f "infrastructure/fluxcd/namespaces/gitops-poc.yaml" ]]; then
        print_status "Applying namespace configuration..."
        kubectl apply -f infrastructure/fluxcd/namespaces/gitops-poc.yaml
    fi
    
    # Apply sources
    if [[ -f "infrastructure/fluxcd/sources/team-a-source.yaml" ]]; then
        print_status "Applying source configurations..."
        kubectl apply -f infrastructure/fluxcd/sources/
    fi
    
    # Apply releases
    if [[ -f "infrastructure/fluxcd/releases/kustomization.yaml" ]]; then
        print_status "Applying release configurations..."
        kubectl apply -k infrastructure/fluxcd/releases/
    fi
    
    print_status "Initial configurations applied"
}

# Function to display next steps
show_next_steps() {
    echo ""
    print_header "Installation Complete!"
    echo ""
    print_status "FluxCD has been successfully installed and configured."
    echo ""
    echo "Next steps:"
    echo "1. Create GitHub Packages secret:"
    echo "   export GITHUB_USERNAME=your-username"
    echo "   export GITHUB_TOKEN=your-token"
    echo "   ./scripts/setup/create-github-packages-secret.sh"
    echo ""
    echo "2. Monitor FluxCD reconciliation:"
    echo "   flux get sources git"
    echo "   flux get helmreleases"
    echo "   kubectl get pods -n gitops-poc"
    echo ""
    echo "3. View logs if needed:"
    echo "   flux logs --follow --tail=10"
    echo ""
    echo "4. Access FluxCD dashboard (optional):"
    echo "   flux install --export > flux-system.yaml"
    echo ""
    print_status "Your GitOps pipeline is ready!"
}

# Main function
main() {
    echo "FluxCD Installation and Bootstrap Script"
    echo "======================================="
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --owner)
                GITHUB_OWNER="$2"
                shift 2
                ;;
            --repository)
                GITHUB_REPOSITORY="$2"
                shift 2
                ;;
            --path)
                FLUX_PATH="$2"
                shift 2
                ;;
            --skip-cli-install)
                SKIP_CLI_INSTALL=true
                shift
                ;;
            --skip-bootstrap)
                SKIP_BOOTSTRAP=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --owner OWNER               GitHub owner/organization (default: $GITHUB_OWNER)
  --repository REPO           GitHub repository (default: $GITHUB_REPOSITORY)
  --path PATH                 Path in repository for FluxCD configs (default: $FLUX_PATH)
  --skip-cli-install         Skip FluxCD CLI installation
  --skip-bootstrap           Skip FluxCD bootstrap
  -h, --help                 Show this help message

Environment Variables:
  GITHUB_TOKEN               GitHub Personal Access Token (required)
  GITHUB_USER                GitHub username (optional, defaults to owner)

Examples:
  # Install with defaults
  export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
  $0

  # Install with custom repository
  $0 --owner myorg --repository my-gitops-repo

  # Skip CLI installation
  $0 --skip-cli-install
EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run installation steps
    check_dependencies
    validate_github_credentials
    
    if [[ "$SKIP_CLI_INSTALL" != "true" ]]; then
        install_flux_cli
    fi
    
    run_precheck
    
    if [[ "$SKIP_BOOTSTRAP" != "true" ]]; then
        bootstrap_flux "$GITHUB_OWNER" "$GITHUB_REPOSITORY" "$FLUX_PATH"
        verify_installation
        
        # Apply initial configs if we're in the right directory
        if [[ -d "infrastructure/fluxcd" ]]; then
            apply_initial_configs
        fi
    fi
    
    show_next_steps
}

# Run main function with all arguments
main "$@"
