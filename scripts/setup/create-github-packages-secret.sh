#!/bin/bash

# GitHub Packages Secret Creation Script
# This script creates the necessary Kubernetes secret for pulling images from GitHub Container Registry

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_NAMESPACE="gitops-poc"
DEFAULT_SECRET_NAME="github-packages-secret"

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

# Function to check if required tools are available
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v base64 &> /dev/null; then
        print_error "base64 is not installed or not in PATH"
        exit 1
    fi
    
    print_status "Dependencies check passed"
}

# Function to validate GitHub credentials
validate_credentials() {
    if [[ -z "$GITHUB_USERNAME" ]]; then
        print_error "GITHUB_USERNAME environment variable is not set"
        echo "Please set it using: export GITHUB_USERNAME=your-github-username"
        exit 1
    fi
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        print_error "GITHUB_TOKEN environment variable is not set"
        echo "Please set it using: export GITHUB_TOKEN=your-github-token"
        echo "The token needs 'packages:read' and 'packages:write' permissions"
        exit 1
    fi
    
    print_status "GitHub credentials validated"
}

# Function to test GitHub authentication
test_github_auth() {
    print_status "Testing GitHub authentication..."
    
    if ! echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin &>/dev/null; then
        print_error "Failed to authenticate with GitHub Container Registry"
        print_error "Please check your GITHUB_USERNAME and GITHUB_TOKEN"
        exit 1
    fi
    
    print_status "GitHub authentication successful"
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        print_status "Namespace '$namespace' already exists"
    else
        print_status "Creating namespace '$namespace'..."
        kubectl create namespace "$namespace"
    fi
}

# Function to create docker config JSON
create_docker_config() {
    local username="$1"
    local token="$2"
    local auth=$(echo -n "$username:$token" | base64 -w 0)
    
    cat <<EOF
{
  "auths": {
    "ghcr.io": {
      "username": "$username",
      "password": "$token",
      "auth": "$auth"
    }
  }
}
EOF
}

# Function to create the secret
create_secret() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local secret_name=${2:-$DEFAULT_SECRET_NAME}
    
    print_status "Creating GitHub Packages secret '$secret_name' in namespace '$namespace'..."
    
    # Create docker config JSON
    local docker_config=$(create_docker_config "$GITHUB_USERNAME" "$GITHUB_TOKEN")
    
    # Check if secret already exists
    if kubectl get secret "$secret_name" -n "$namespace" &>/dev/null; then
        print_warning "Secret '$secret_name' already exists in namespace '$namespace'"
        read -p "Do you want to replace it? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping secret creation"
            return 0
        fi
        kubectl delete secret "$secret_name" -n "$namespace"
    fi
    
    # Create the secret
    kubectl create secret generic "$secret_name" \
        --from-literal=.dockerconfigjson="$docker_config" \
        --type=kubernetes.io/dockerconfigjson \
        --namespace="$namespace"
    
    # Add labels
    kubectl label secret "$secret_name" \
        app.kubernetes.io/name="$secret_name" \
        app.kubernetes.io/part-of=gitops-poc \
        github.com/packages-integration=true \
        --namespace="$namespace"
    
    print_status "Secret '$secret_name' created successfully"
}

# Function to verify the secret
verify_secret() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local secret_name=${2:-$DEFAULT_SECRET_NAME}
    
    print_status "Verifying secret '$secret_name'..."
    
    if kubectl get secret "$secret_name" -n "$namespace" &>/dev/null; then
        print_status "Secret exists and is accessible"
        
        # Show secret details (without revealing the actual token)
        echo ""
        echo "Secret Details:"
        kubectl describe secret "$secret_name" -n "$namespace"
        
        return 0
    else
        print_error "Secret verification failed"
        return 1
    fi
}

# Function to create a test pod to verify image pull
create_test_pod() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local secret_name=${2:-$DEFAULT_SECRET_NAME}
    
    print_status "Creating test pod to verify image pull capabilities..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: github-packages-test
  namespace: $namespace
  labels:
    test: github-packages
spec:
  restartPolicy: Never
  imagePullSecrets:
    - name: $secret_name
  containers:
  - name: test
    image: ghcr.io/duggireddy-nsf/team-a-service:latest
    command: ['echo', 'Image pull successful']
  activeDeadlineSeconds: 300
EOF

    # Wait for pod to complete
    print_status "Waiting for test pod to complete..."
    kubectl wait --for=condition=Ready pod/github-packages-test -n "$namespace" --timeout=300s || true
    
    # Check pod status
    local pod_status=$(kubectl get pod github-packages-test -n "$namespace" -o jsonpath='{.status.phase}')
    
    if [[ "$pod_status" == "Succeeded" || "$pod_status" == "Running" ]]; then
        print_status "Image pull test successful"
    else
        print_warning "Image pull test failed or pod is still running"
        echo "Pod status: $pod_status"
        echo "Pod logs:"
        kubectl logs github-packages-test -n "$namespace" || true
        echo ""
        echo "Pod events:"
        kubectl describe pod github-packages-test -n "$namespace" | grep Events -A 10 || true
    fi
    
    # Cleanup test pod
    kubectl delete pod github-packages-test -n "$namespace" --ignore-not-found=true
}

# Main function
main() {
    echo "GitHub Packages Secret Setup Script"
    echo "==================================="
    echo ""
    
    # Parse command line arguments
    NAMESPACE="$DEFAULT_NAMESPACE"
    SECRET_NAME="$DEFAULT_SECRET_NAME"
    SKIP_TEST=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -s|--secret-name)
                SECRET_NAME="$2"
                shift 2
                ;;
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -n, --namespace NAMESPACE    Kubernetes namespace (default: $DEFAULT_NAMESPACE)
  -s, --secret-name NAME       Secret name (default: $DEFAULT_SECRET_NAME)
      --skip-test             Skip image pull test
  -h, --help                  Show this help message

Environment Variables:
  GITHUB_USERNAME              GitHub username (required)
  GITHUB_TOKEN                 GitHub personal access token (required)
                              Must have 'packages:read' and 'packages:write' permissions

Examples:
  # Create secret with defaults
  export GITHUB_USERNAME=myuser
  export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
  $0

  # Create secret in custom namespace
  $0 --namespace my-namespace

  # Create secret with custom name and skip test
  $0 --secret-name my-secret --skip-test
EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run setup steps
    check_dependencies
    validate_credentials
    test_github_auth
    create_namespace "$NAMESPACE"
    create_secret "$NAMESPACE" "$SECRET_NAME"
    verify_secret "$NAMESPACE" "$SECRET_NAME"
    
    if [[ "$SKIP_TEST" == "false" ]]; then
        create_test_pod "$NAMESPACE" "$SECRET_NAME"
    fi
    
    echo ""
    print_status "GitHub Packages secret setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Your applications can now use imagePullSecrets:"
    echo "   imagePullSecrets:"
    echo "     - name: $SECRET_NAME"
    echo ""
    echo "2. Apply your FluxCD configurations to start GitOps deployments"
    echo "3. Monitor deployments with: kubectl get pods -n $NAMESPACE"
}

# Run main function with all arguments
main "$@"
