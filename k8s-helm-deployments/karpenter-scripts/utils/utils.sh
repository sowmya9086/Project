#!/bin/bash

# utils.sh - Utility functions for Karpenter automation
# This script contains common utility functions used across multiple Karpenter scripts

# Color functions for terminal output
set_green() {
    echo -e "\033[92m"
}

set_red() {
    echo -e "\033[91m"   
}

set_blue() {
    echo -e "\033[34m"
}

set_default() {
    echo -e "\033[39m"   
}

set_yellow() {
    echo -e "\033[33m"
}

# Pause function for user interaction
pause() {
    set_yellow
    echo "Hit enter to proceed"
    read
    set_default
}

# Dump variables for debugging
dump_vars() {
    set_blue
    echo "KARPENTER_INSTALLED is ${KARPENTER_INSTALLED}"
    echo "REGION is ${AWS_REGION}"
    echo "ACCT is ${AWS_ACCOUNT_ID}"
    echo "OIDC is ${OIDC_ENDPOINT}"
    echo "OIDC_SHORT is ${OIDC_SHORT}"
    echo "CLUSTER_NAME is ${CLUSTER_NAME}"
    echo "KARPENTER_VERSION is ${KARPENTER_VERSION}"
    set_default
    pause
}

# Get Karpenter logs
get_logs() {
    echo "Getting logs"
    kubectl logs -f -n karpenter -c controller -l app.kubernetes.io/name=karpenter
}

# Get all nodes
get_nodes() {
    echo "Getting nodes"
    kubectl get nodes
}

# Create test deployment to validate Karpenter functionality
deployment_test() {
    cat<<EOF > deployment_test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      nodeSelector:
        nodetype: defaultkarpenter
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources:
            requests:
              cpu: 1
EOF
    echo "Deploying test deployment to validate..."
    kubectl apply -f deployment_test.yaml
}

# Fix CRDs annotations (if needed)
fix_crds() {
    kubectl annotate crd awsnodetemplates.karpenter.k8s.aws provisioners.karpenter.sh machines.karpenter.sh meta.helm.sh/release-name=karpenter-crd --overwrite
    kubectl annotate crd awsnodetemplates.karpenter.k8s.aws provisioners.karpenter.sh machines.karpenter.sh meta.helm.sh/release-namespace=karpenter --overwrite
}

# Cleanup test deployment
cleanup_test_deployment() {
    echo "Deleting test deployment if it exists"
    kubectl delete deployment inflate -n karpenter 2>/dev/null || true
}

# Display script header
show_header() {
    local script_name="$1"
    local description="$2"
    
    set_blue
    echo "=================================="
    echo "  $script_name"
    echo "  $description"
    echo "=================================="
    set_default
}

# Validate required environment variables
validate_environment() {
    local required_vars=("CLUSTER_NAME" "AWS_REGION" "AWS_ACCOUNT_ID" "KARPENTER_VERSION")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -ne 0 ]]; then
        set_red
        echo "Error: Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        set_default
        return 1
    fi
    
    return 0
}

# Check if kubectl is available and cluster is accessible
check_kubectl_access() {
    if ! command -v kubectl &> /dev/null; then
        set_red
        echo "Error: kubectl is not installed or not in PATH"
        set_default
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        set_red
        echo "Error: Cannot access Kubernetes cluster. Check your kubeconfig."
        set_default
        return 1
    fi
    
    return 0
}

# Check if AWS CLI is available and configured
check_aws_access() {
    if ! command -v aws &> /dev/null; then
        set_red
        echo "Error: aws CLI is not installed or not in PATH"
        set_default
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        set_red
        echo "Error: AWS CLI is not configured or credentials are invalid"
        set_default
        return 1
    fi
    
    return 0
}

# Display success message
show_success() {
    local message="$1"
    set_green
    echo "✓ $message"
    set_default
}

# Display error message
show_error() {
    local message="$1"
    set_red
    echo "✗ Error: $message"
    set_default
}

# Display info message
show_info() {
    local message="$1"
    set_blue
    echo "ℹ $message"
    set_default
}

# Display warning message
show_warning() {
    local message="$1"
    set_yellow
    echo "⚠ Warning: $message"
    set_default
}
