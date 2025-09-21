#!/bin/bash

# provisioner-management.sh - Provisioner management functions for Karpenter
# This script contains functions to create and manage Karpenter provisioners and node templates

# Source utility functions
PROVISIONER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PROVISIONER_SCRIPT_DIR}/../utils/utils.sh"

# Verify provisioners
verify_provisioners() {
    show_header "Provisioner Verification" "Checking deployed provisioners"
    
    echo "Provisioners deployed (should be 1: defaultkarpenter):"
    if kubectl get provisioners -o wide 2>/dev/null; then
        show_success "Retrieved provisioners"
    else
        show_warning "No provisioners found or using newer API version"
    fi
    
    echo "AWSNodeTemplates deployed (should be 1: defaultkarpenter):"
    if kubectl get awsnodetemplates -o wide 2>/dev/null; then
        show_success "Retrieved AWSNodeTemplates"
    else
        show_warning "No AWSNodeTemplates found or using newer API version"
    fi
    
    # Check for newer v1beta1 resources
    echo "NodePools (v1beta1):"
    if kubectl get nodepools -o wide 2>/dev/null; then
        show_success "Retrieved NodePools"
    else
        show_info "No NodePools found"
    fi
    
    echo "EC2NodeClasses (v1beta1):"
    if kubectl get ec2nodeclasses -o wide 2>/dev/null; then
        show_success "Retrieved EC2NodeClasses"
    else
        show_info "No EC2NodeClasses found"
    fi
    
    return 0
}

# Create default provisioner (v1alpha5)
create_default_provisioner() {
    show_info "Creating default provisioner"
    
    cat<<EOF > defaultkarpenter_provisioner.yaml 
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: defaultkarpenter
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"]
    - key: "karpenter.k8s.aws/instance-category"
      operator: In
      values: ["m"]
    - key: "karpenter.k8s.aws/instance-size"
      operator: In
      values: ["4xlarge","2xlarge", "large", "xlarge", "medium"]
    - key: "kubernetes.io/arch" 
      operator: In
      values: ["amd64"]
  providerRef:
    name: defaultkarpenter
  ttlSecondsAfterEmpty: 30
  # Labels are arbitrary key-values that are applied to all nodes
  labels:
    nodetype: defaultkarpenter
EOF

    kubectl apply -f defaultkarpenter_provisioner.yaml
}

# Create default AWS node template (v1alpha1)
create_default_nodetemplate() {
    show_info "Creating default AWS node template"
    
    cat<<EOF > defaultkarpenter_awsnodetemplate.yaml
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: defaultkarpenter
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
    Area: Karpenter
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeType: gp3
      volumeSize: 50Gi
      deleteOnTermination: true
EOF

    kubectl apply -f defaultkarpenter_awsnodetemplate.yaml
}



# Create all standard provisioners (v1alpha5)
create_provisioners() {
    show_header "Standard Provisioner Creation" "Creating default Karpenter provisioners"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_kubectl_access; then
        return 1
    fi
    
    echo "Creating provisioners for Karpenter v1alpha5 API"
    
    # Create default provisioner and node template
    create_default_provisioner
    create_default_nodetemplate
    
    show_success "Default provisioner and AWSNodeTemplate deployed"
    verify_provisioners
    
    return 0
}


# Create NodePools (v1beta1 API - newer versions)
create_nodepools() {
    show_header "NodePool Creation" "Creating NodePools for Karpenter v1beta1"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_kubectl_access; then
        return 1
    fi
    
    echo "Creating NodePools for Karpenter v1beta1 API"
    
    # Create default nodepool
    cat <<EOF > defaultkarpenter_nodepool.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: defaultkarpenter
  labels:
    nodetype: defaultkarpenter
  annotations:
    kubernetes.io/description: "General purpose NodePool for generic workloads"
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["m"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
        - key: nodetype
          operator: In
          values: ["defaultkarpenter"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: defaultkarpenter

---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: defaultkarpenter
spec:
  amiFamily: Bottlerocket
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  tags:
    karpenter.sh/discovery: "${CLUSTER_NAME}"
    Department: "QA"
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
        volumeType: gp3
        volumeSize: 50Gi
        deleteOnTermination: true
EOF
    kubectl apply -f defaultkarpenter_nodepool.yaml
    
    show_success "Default NodePool and EC2NodeClass deployed"
    verify_provisioners
    
    return 0
}

# Remove only extra provisioners (keep default)
remove_extra_provisioners() {
    show_header "Extra Provisioner Cleanup" "Removing extra provisioners while keeping default ones"
    
    if ! check_kubectl_access; then
        return 1
    fi
    
    echo "Removing extra provisioners (keeping defaultkarpenter)..."
    kubectl delete provisioner bas-benchmarklarge bas-feature-testing bas-sbom benchmarklarge-karpenter feature-testing-karpenter sbom-karpenter bas-karpenter karpenter_storage karpentercarbon 2>/dev/null || true
    
    echo "Removing extra AWSNodeTemplates (keeping defaultkarpenter)..."
    kubectl delete awsnodetemplate bas-benchmarklarge bas-feature-testing bas-sbom benchmarklarge-karpenter feature-testing-karpenter sbom-karpenter bas-karpenter karpenter_storage karpentercarbon 2>/dev/null || true
    
    echo "Removing extra NodePools (keeping defaultkarpenter)..."
    kubectl delete nodepool bas-karpenter karpentercarbon 2>/dev/null || true
    
    echo "Removing extra EC2NodeClasses (keeping defaultkarpenter)..."
    kubectl delete ec2nodeclass bas-karpenter karpentercarbon 2>/dev/null || true
    
    show_success "Extra provisioner cleanup completed - only defaultkarpenter resources remain"
    
    # Verify what remains
    echo "\nVerifying remaining resources:"
    verify_provisioners
    
    return 0
}

# Remove all provisioners
remove_provisioners() {
    show_header "Provisioner Removal" "Removing all provisioners and node templates"
    
    if ! check_kubectl_access; then
        return 1
    fi
    
    echo "Removing all provisioners and AWSNodeTemplates..."
    kubectl delete provisioner defaultkarpenter 2>/dev/null || true
    kubectl delete awsnodetemplate defaultkarpenter 2>/dev/null || true
    
    echo "Removing all NodePools and EC2NodeClasses..."
    kubectl delete nodepool defaultkarpenter 2>/dev/null || true
    kubectl delete ec2nodeclass defaultkarpenter 2>/dev/null || true
    
    show_success "All provisioner removal completed"
    return 0
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_error "This script should be sourced, not executed directly"
    echo "Usage: source provisioner-management.sh"
    exit 1
fi
