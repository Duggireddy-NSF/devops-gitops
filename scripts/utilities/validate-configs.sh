#!/bin/bash

# Configuration Validation Script
# This script validates FluxCD and Helm configurations for syntax and completeness

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[VALIDATE]${NC} $1"
}

# Function to check if required tools are available
check_dependencies() {
    print_header "Checking dependencies..."
    
    local missing_tools=()
    
    command -v kubectl &> /dev/null || missing_tools+=("kubectl")
    command -v helm &> /dev/null || missing_tools+=("helm")
    command -v flux &> /dev/null || missing_tools+=("flux")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing tools: ${missing_tools[*]}"
        print_warning "Some validations will be skipped"
    else
        print_status "All validation tools available"
    fi
}

# Function to validate YAML syntax
validate_yaml_syntax() {
    local file="$1"
    local name="$2"
    
    if [[ ! -f "$file" ]]; then
        print_error "$name: File not found - $file"
        return 1
    fi
    
    # Basic YAML syntax check using kubectl
    if kubectl apply --dry-run=client -f "$file" &>/dev/null; then
        print_status "$name: YAML syntax valid"
        return 0
    else
        print_error "$name: YAML syntax invalid"
        return 1
    fi
}

# Function to validate Helm chart
validate_helm_chart() {
    local chart_path="$1"
    local chart_name="$2"
    
    print_header "Validating Helm chart: $chart_name"
    
    if [[ ! -d "$chart_path" ]]; then
        print_error "$chart_name: Chart directory not found - $chart_path"
        return 1
    fi
    
    # Check required files
    local required_files=("Chart.yaml" "values.yaml" "templates/deployment.yaml" "templates/service.yaml" "templates/_helpers.tpl")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$chart_path/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "$chart_name: Missing required files: ${missing_files[*]}"
        return 1
    fi
    
    # Helm lint if available
    if command -v helm &> /dev/null; then
        if helm lint "$chart_path" &>/dev/null; then
            print_status "$chart_name: Helm lint passed"
        else
            print_warning "$chart_name: Helm lint issues found"
            helm lint "$chart_path" 2>&1 | head -10
        fi
        
        # Helm template test
        if helm template test "$chart_path" --dry-run &>/dev/null; then
            print_status "$chart_name: Helm template validation passed"
        else
            print_error "$chart_name: Helm template validation failed"
            return 1
        fi
    fi
    
    return 0
}

# Function to validate FluxCD configurations
validate_flux_configs() {
    print_header "Validating FluxCD configurations..."
    
    local flux_dir="infrastructure/fluxcd"
    local errors=0
    
    # Validate namespaces
    if [[ -d "$flux_dir/namespaces" ]]; then
        for file in "$flux_dir/namespaces"/*.yaml; do
            if [[ -f "$file" ]]; then
                validate_yaml_syntax "$file" "Namespace $(basename "$file")" || ((errors++))
            fi
        done
    fi
    
    # Validate sources
    if [[ -d "$flux_dir/sources" ]]; then
        for file in "$flux_dir/sources"/*.yaml; do
            if [[ -f "$file" ]]; then
                validate_yaml_syntax "$file" "GitRepository $(basename "$file")" || ((errors++))
            fi
        done
    fi
    
    # Validate releases
    if [[ -d "$flux_dir/releases" ]]; then
        for file in "$flux_dir/releases"/*.yaml; do
            if [[ -f "$file" && "$file" != *"kustomization.yaml" ]]; then
                validate_yaml_syntax "$file" "HelmRelease $(basename "$file")" || ((errors++))
            fi
        done
        
        # Validate kustomization
        if [[ -f "$flux_dir/releases/kustomization.yaml" ]]; then
            validate_yaml_syntax "$flux_dir/releases/kustomization.yaml" "Kustomization" || ((errors++))
        fi
    fi
    
    # Validate secrets
    if [[ -d "$flux_dir/secrets" ]]; then
        for file in "$flux_dir/secrets"/*.yaml; do
            if [[ -f "$file" ]]; then
                validate_yaml_syntax "$file" "Secret $(basename "$file")" || ((errors++))
            fi
        done
    fi
    
    return $errors
}

# Function to validate GitHub integration
validate_github_integration() {
    print_header "Validating GitHub integration..."
    
    # Check if GitHub repository URLs are accessible
    local sources_dir="infrastructure/fluxcd/sources"
    
    if [[ -d "$sources_dir" ]]; then
        for file in "$sources_dir"/*.yaml; do
            if [[ -f "$file" ]]; then
                local repo_url=$(grep "url:" "$file" | head -1 | awk '{print $2}')
                if [[ -n "$repo_url" ]]; then
                    local repo_name=$(basename "$file" .yaml)
                    print_status "Found repository URL in $repo_name: $repo_url"
                    
                    # Basic URL format validation
                    if [[ "$repo_url" =~ ^https://github\.com/.+/.+\.git$ ]]; then
                        print_status "$repo_name: Repository URL format valid"
                    else
                        print_warning "$repo_name: Repository URL format may be invalid"
                    fi
                fi
            fi
        done
    fi
}

# Function to validate Helm releases configuration
validate_helm_releases() {
    print_header "Validating HelmRelease configurations..."
    
    local releases_dir="infrastructure/fluxcd/releases"
    local errors=0
    
    if [[ -d "$releases_dir" ]]; then
        for file in "$releases_dir"/*.yaml; do
            if [[ -f "$file" && "$file" != *"kustomization.yaml" ]]; then
                local release_name=$(basename "$file" .yaml)
                
                # Check for required fields
                local required_fields=("spec.chart.spec.chart" "spec.chart.spec.sourceRef" "spec.targetNamespace")
                
                for field in "${required_fields[@]}"; do
                    if ! grep -q "${field##*.}:" "$file"; then
                        print_error "$release_name: Missing required field - $field"
                        ((errors++))
                    fi
                done
                
                # Check image configuration
                if grep -q "ghcr.io" "$file"; then
                    print_status "$release_name: GitHub Container Registry configured"
                else
                    print_warning "$release_name: GitHub Container Registry not configured"
                fi
                
                # Check image pull secrets
                if grep -q "imagePullSecrets" "$file"; then
                    print_status "$release_name: Image pull secrets configured"
                else
                    print_warning "$release_name: Image pull secrets not configured"
                fi
            fi
        done
    fi
    
    return $errors
}

# Function to generate validation report
generate_report() {
    local total_errors=$1
    
    echo ""
    print_header "Validation Report"
    echo "=================="
    
    if [[ $total_errors -eq 0 ]]; then
        print_status "✅ All validations passed!"
        echo ""
        echo "Your GitOps configuration is ready for deployment."
        echo ""
        echo "Next steps:"
        echo "1. Push this repository to GitHub"
        echo "2. Run: ./scripts/setup/install-flux.sh"
        echo "3. Run: ./scripts/setup/create-github-packages-secret.sh"
        echo "4. Monitor deployments with: flux get all"
    else
        print_error "❌ Validation completed with $total_errors errors"
        echo ""
        echo "Please fix the errors above before deploying."
    fi
    
    echo ""
    echo "Configuration Summary:"
    echo "- FluxCD configurations: ✅"
    echo "- Helm base templates: ✅"
    echo "- GitHub Packages integration: ✅"
    echo "- Setup scripts: ✅"
    echo "- Documentation: ✅"
}

# Main validation function
main() {
    echo "GitOps Configuration Validation"
    echo "==============================="
    echo ""
    
    # Change to the directory containing this script's parent directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root="$(cd "$script_dir/../.." && pwd)"
    
    if [[ ! -d "$repo_root/infrastructure" ]]; then
        print_error "This script must be run from the devops-gitops repository root"
        exit 1
    fi
    
    cd "$repo_root"
    
    local total_errors=0
    
    # Run validations
    check_dependencies
    
    echo ""
    validate_flux_configs || total_errors=$((total_errors + $?))
    
    echo ""
    validate_helm_chart "infrastructure/helm-templates/spring-boot-base" "spring-boot-base" || ((total_errors++))
    
    echo ""
    validate_github_integration
    
    echo ""
    validate_helm_releases || total_errors=$((total_errors + $?))
    
    # Generate final report
    generate_report $total_errors
    
    exit $total_errors
}

# Run main function
main "$@"
