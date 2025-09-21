#!/bin/bash

# karpenter-deploy.sh - Karpenter deployment functions
# This script contains functions to deploy Karpenter v0.33.1 to the EKS cluster

# Source utility functions
DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DEPLOY_SCRIPT_DIR}/../utils/utils.sh"

# Set Karpenter version
export KARPENTER_VERSION="v0.33.1"

# Create Karpenter CRDs for v0.33.1
create_crds() {
    show_header "CRD Deployment" "Creating Karpenter v0.33.1 Custom Resource Definitions"
    
    show_info "Deploying CRDs for Karpenter v0.33.1"
    local crd_urls=(
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.sh_nodepools.yaml"
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"
    )
    
    # Deploy each CRD
    for crd_url in "${crd_urls[@]}"; do
        local crd_name=$(basename "$crd_url")
        echo "Deploying CRD: $crd_name"
        
        if kubectl create -f "$crd_url"; then
            show_success "Deployed CRD: $crd_name"
        else
            show_warning "CRD may already exist: $crd_name"
        fi
    done
    
    show_success "CRD deployment completed"
    return 0
}

# Generate Karpenter affinity configuration
generate_karpenter_affinity() {
    show_info "Generating Karpenter affinity configuration"
    
    cat > karpenter_affinity.yaml << '_EOF_'
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      preference:
        matchExpressions:
              - key: cluster
                operator: In
                values:
                - resources
_EOF_
    
    show_success "Generated karpenter_affinity.yaml"
}

# Generate Helm template for Karpenter v0.33.1
generate_helm_template() {
    show_header "Helm Template Generation" "Creating Karpenter v0.33.1 Helm template"
    
    local template_file="${CLUSTER_NAME}_karpenter.yaml"
    
    # Generate affinity configuration
    generate_karpenter_affinity
    
    show_info "Generating Helm template for Karpenter v0.33.1"
    
    helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
        --version "v0.33.1" \
        --namespace "${KARPENTER_NAMESPACE}" \
        --set "settings.clusterName=${CLUSTER_NAME}" \
        --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
        --set controller.resources.requests.cpu=1 \
        --set controller.resources.requests.memory=1Gi \
        --set controller.resources.limits.cpu=1 \
        --set controller.resources.limits.memory=1Gi \
        -f karpenter_affinity.yaml > "$template_file"
    
    if [[ -f "$template_file" ]]; then
        show_success "Generated Helm template: $template_file"
        return 0
    else
        show_error "Failed to generate Helm template"
        return 1
    fi
}

# Deploy Karpenter to the cluster
deploy_Karpenter() {
    show_header "Karpenter Deployment" "Deploying Karpenter to EKS cluster"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_aws_access || ! check_kubectl_access; then
        return 1
    fi
    
    # Create namespace
    echo "Creating namespace: ${KARPENTER_NAMESPACE}"
    if kubectl create namespace "${KARPENTER_NAMESPACE}"; then
        show_success "Created namespace: ${KARPENTER_NAMESPACE}"
    else
        show_warning "Namespace ${KARPENTER_NAMESPACE} may already exist"
    fi
    
    # Set namespace context
    echo "Setting namespace context..."
    kubectl config set-context --current --namespace="${KARPENTER_NAMESPACE}"
    show_success "Set context to namespace: ${KARPENTER_NAMESPACE}"
    
    # Deploy CRDs
    echo "Deploying CRDs..."
    if ! create_crds; then
        show_error "Failed to deploy CRDs"
        return 1
    fi
    
    # Associate OIDC provider
    echo "Adding OIDC provider (may error if already exists)..."
    if eksctl utils associate-iam-oidc-provider \
        --region="${AWS_REGION}" \
        --cluster="${CLUSTER_NAME}" \
        --approve; then
        show_success "Associated OIDC provider"
    else
        show_warning "OIDC provider may already be associated"
    fi
    
    # Generate and apply Helm template
    echo "Generating Karpenter Helm template..."
    if ! generate_helm_template; then
        show_error "Failed to generate Helm template"
        return 1
    fi
    
    # Apply the template
    local template_file="${CLUSTER_NAME}_karpenter.yaml"
    echo "Deploying Karpenter via kubectl apply..."
    if kubectl apply -f "$template_file"; then
        show_success "Deployed Karpenter successfully"
    else
        show_error "Failed to deploy Karpenter"
        return 1
    fi
    
    show_info "Check out ~/${PWD}/${template_file} for deployed Karpenter settings"
    
    # Wait for deployment to be ready
    echo "Waiting for Karpenter deployment to be ready..."
    if kubectl wait --for=condition=Available --timeout=300s deployment/karpenter -n "${KARPENTER_NAMESPACE}"; then
        show_success "Karpenter deployment is ready"
    else
        show_warning "Karpenter deployment may still be starting up"
    fi
    
    # Cleanup temporary files
    rm -f karpenter_affinity.yaml
    
    show_success "Karpenter deployment completed successfully"
    return 0
}

# Remove Karpenter from the cluster
remove_karpenter() {
    show_header "Karpenter Removal" "Removing Karpenter from EKS cluster"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_kubectl_access; then
        return 1
    fi
    
    echo "Removing Karpenter from cluster: ${CLUSTER_NAME}"
    
    # Remove test deployment
    cleanup_test_deployment
    
    # Check if Karpenter template exists, create if needed for removal
    local template_file="${CLUSTER_NAME}_karpenter.yaml"
    if [[ ! -f "$template_file" ]]; then
        show_warning "${template_file} not found, re-creating it for removal..."
        
        generate_karpenter_affinity
        
        helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
            --version "v0.33.1" \
            --namespace "${KARPENTER_NAMESPACE}" \
            --set "settings.clusterName=${CLUSTER_NAME}" \
            --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
            --set controller.resources.requests.cpu=1 \
            --set controller.resources.requests.memory=1Gi \
            --set controller.resources.limits.cpu=1 \
            --set controller.resources.limits.memory=1Gi > "$template_file"
        
        rm -f karpenter_affinity.yaml
    fi
    
    # Remove Karpenter using the template
    echo "Deleting Karpenter resources using ${template_file}..."
    if kubectl delete -f "$template_file" -n "${KARPENTER_NAMESPACE}"; then
        show_success "Deleted Karpenter resources"
    else
        show_warning "Some Karpenter resources may not exist"
    fi
    
    # Remove CRDs for v0.33.1
    echo "Deleting v0.33.1 CRDs..."
    local crd_urls=(
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.sh_nodepools.yaml"
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
        "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"
    )
    
    for crd_url in "${crd_urls[@]}"; do
        local crd_name=$(basename "$crd_url")
        echo "Deleting CRD: $crd_name"
        kubectl delete -f "$crd_url" 2>/dev/null || show_warning "CRD may not exist: $crd_name"
    done
    
    # Remove namespace
    echo "Deleting namespace: ${KARPENTER_NAMESPACE}"
    if kubectl delete namespace "${KARPENTER_NAMESPACE}"; then
        show_success "Deleted namespace: ${KARPENTER_NAMESPACE}"
    else
        show_warning "Namespace may not exist or may contain resources"
    fi
    
    show_success "Karpenter removal completed"
    echo "Note: IAM roles, policies, and CloudFormation stacks need to be cleaned up manually if no longer needed"
    
    return 0
}

# Verify Karpenter deployment
verify_karpenter_deployment() {
    show_header "Deployment Verification" "Verifying Karpenter deployment"
    
    # Check if namespace exists
    if kubectl get namespace "${KARPENTER_NAMESPACE}" &>/dev/null; then
        show_success "Namespace ${KARPENTER_NAMESPACE} exists"
    else
        show_error "Namespace ${KARPENTER_NAMESPACE} not found"
        return 1
    fi
    
    # Check if Karpenter deployment is running
    if kubectl get deployment karpenter -n "${KARPENTER_NAMESPACE}" &>/dev/null; then
        local status
        status=$(kubectl get deployment karpenter -n "${KARPENTER_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        if [[ "$status" == "True" ]]; then
            show_success "Karpenter deployment is available"
        else
            show_warning "Karpenter deployment may not be ready yet"
        fi
    else
        show_error "Karpenter deployment not found"
        return 1
    fi
    
    # Check v0.33.1 CRDs
    local expected_crds=("nodepools.karpenter.sh" "ec2nodeclasses.karpenter.k8s.aws" "nodeclaims.karpenter.sh")
    
    local crd_check_passed=true
    for crd in "${expected_crds[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
            show_success "CRD found: $crd"
        else
            show_error "CRD missing: $crd"
            crd_check_passed=false
        fi
    done
    
    if [[ "$crd_check_passed" == "false" ]]; then
        return 1
    fi
    
    # Show all resources in karpenter namespace
    echo ""
    echo "All resources in ${KARPENTER_NAMESPACE} namespace:"
    kubectl get all -n "${KARPENTER_NAMESPACE}"
    
    show_success "Karpenter deployment verification completed"
    return 0
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_error "This script should be sourced, not executed directly"
    echo "Usage: source karpenter-deploy.sh"
    exit 1
fi
