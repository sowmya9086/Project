#!/bin/bash

# iam-verify.sh - IAM verification functions for Karpenter
# This script contains functions to verify IAM roles and policies required for Karpenter

# Source utility functions
IAM_VERIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${IAM_VERIFY_SCRIPT_DIR}/../utils/utils.sh"

# Verify Karpenter Node Role
verify_Karpenter_Node_Role() {
    show_header "Node Role Verification" "Verifying Karpenter Node Role"
    
    echo "Verifying IAM role KarpenterNodeRole-${CLUSTER_NAME}"
    
    # Get the role and check its trust policy
    local role_info
    if role_info=$(aws iam get-role --role-name "KarpenterNodeRole-${CLUSTER_NAME}" 2>/dev/null); then
        if echo "$role_info" | grep -q "ec2.amazonaws.com" && \
           echo "$role_info" | grep -q "Allow" && \
           echo "$role_info" | grep -q "sts:AssumeRole"; then
            show_success "Node role trust policy is correct"
        else
            show_error "Node role trust policy is incorrect"
            set_yellow
            echo "$role_info"
            set_default
            pause
            return 1
        fi
    else
        show_error "KarpenterNodeRole-${CLUSTER_NAME} not found"
        return 1
    fi
    
    # Check attached policies
    echo "Verifying attached policies for Node Role:"
    local policies
    if policies=$(aws iam list-role-policies --role-name "KarpenterNodeRole-${CLUSTER_NAME}" 2>/dev/null); then
        show_info "Inline policies: $policies"
    fi
    
    # Check attached managed policies
    local managed_policies
    if managed_policies=$(aws iam list-attached-role-policies --role-name "KarpenterNodeRole-${CLUSTER_NAME}" 2>/dev/null); then
        local expected_policies=(
            "AmazonEKSWorkerNodePolicy"
            "AmazonEKS_CNI_Policy"
            "AmazonEC2ContainerRegistryReadOnly"
            "AmazonSSMManagedInstanceCore"
        )
        
        local all_found=true
        for policy in "${expected_policies[@]}"; do
            if echo "$managed_policies" | grep -q "$policy"; then
                show_success "Found required policy: $policy"
            else
                show_error "Missing required policy: $policy"
                all_found=false
            fi
        done
        
        if [ "$all_found" = true ]; then
            show_success "All required managed policies are attached"
        else
            show_error "Some required managed policies are missing"
            return 1
        fi
    else
        show_error "Could not list attached managed policies"
        return 1
    fi
    
    # Check instance profile
    if aws iam get-instance-profile --instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}" &>/dev/null; then
        show_success "Instance profile KarpenterNodeInstanceProfile-${CLUSTER_NAME} exists"
    else
        show_error "Instance profile KarpenterNodeInstanceProfile-${CLUSTER_NAME} not found"
        return 1
    fi
    
    return 0
}

# Verify Karpenter Controller Role
verify_Karpenter_Controller_Role() {
    show_header "Controller Role Verification" "Verifying Karpenter Controller Role"
    
    echo "Verifying Karpenter Controller Role"
    
    set_blue
    echo "Manual verification required:"
    echo "Looking for:"
    echo "- sts:AssumeRoleWithWebIdentity"
    echo "- ${OIDC_SHORT}:aud = sts.amazonaws.com"
    echo "- ${OIDC_SHORT}:sub = system:serviceaccount:karpenter:karpenter"
    set_default
    
    set_yellow
    if aws iam get-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" 2>/dev/null; then
        show_success "Controller role exists"
    else
        show_error "KarpenterControllerRole-${CLUSTER_NAME} not found"
        pause
        return 1
    fi
    set_default
    
    pause
    
    echo "Policies assigned to KarpenterControllerRole-${CLUSTER_NAME}:"
    set_blue
    echo "Should show: KarpenterControllerPolicy-${CLUSTER_NAME}"
    set_yellow
    
    if aws iam list-role-policies --role-name "KarpenterControllerRole-${CLUSTER_NAME}" 2>/dev/null; then
        show_success "Listed controller role policies"
    else
        show_error "Could not list controller role policies"
        pause
        return 1
    fi
    set_default
    
    pause
    return 0
}

# Verify AWS auth configmap
verify_aws() {
    show_header "AWS Auth ConfigMap" "Verifying aws-auth configmap"
    
    echo "Verifying aws auth configmap"
    echo "Manual validation required. Your config map should look something like this:"
    
    set_blue
    cat<<EOF
- groups:
  - system:bootstrappers
  - system:nodes
  rolearn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}
  username: system:node:{{EC2PrivateDNSName}}
- groups: 
  - system:bootstrappers 
  - system:nodes 
  rolearn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter-*
  username: system:node:{{EC2PrivateDNSName}}
EOF
    
    set_yellow
    echo "Current aws-auth configmap:"
    if kubectl get cm aws-auth -n kube-system -o json 2>/dev/null | jq -Crj '.data.mapRoles' 2>/dev/null; then
        show_success "Retrieved aws-auth configmap"
    else
        show_warning "Could not retrieve aws-auth configmap or jq not available"
        echo "Trying alternative method:"
        kubectl get cm aws-auth -n kube-system -o yaml 2>/dev/null | grep -A 20 "mapRoles:" || show_error "Could not retrieve configmap"
    fi
    set_default
    
    pause
    return 0
}

# Check service account annotations
check_service_account_annotations() {
    show_header "Service Account Verification" "Checking service account annotations"
    
    local role_arn_validate
    local expected_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}"
    
    if role_arn_validate=$(kubectl get sa karpenter -n "${KARPENTER_NAMESPACE}" -o json 2>/dev/null | jq -Cjr '.metadata.annotations."eks.amazonaws.com/role-arn"' 2>/dev/null); then
        if [[ "$role_arn_validate" == "$expected_arn" ]]; then
            show_success "Service account annotation is correct"
            set_blue
            echo "Service account annotation: $role_arn_validate"
            set_default
        elif [[ "$role_arn_validate" == "null" || -z "$role_arn_validate" ]]; then
            show_error "Service account annotation is missing"
            echo "Expected: $expected_arn"
            pause
            return 1
        else
            show_warning "Service account annotation may be incorrect"
            echo "Expected: $expected_arn"
            echo "Actual: $role_arn_validate"
            
            set_blue
            echo "Manual validation required. Please verify the annotation is correct."
            set_default
            pause
        fi
    else
        show_error "Could not retrieve service account or jq not available"
        echo "Trying alternative method:"
        kubectl get sa karpenter -n "${KARPENTER_NAMESPACE}" -o yaml 2>/dev/null || show_error "Service account not found"
        pause
        return 1
    fi
    
    return 0
}

# Verify OIDC provider exists
verify_oidc_provider() {
    show_header "OIDC Provider Verification" "Checking OIDC provider configuration"
    
    local oidc_id="${OIDC_ENDPOINT#*//}"
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidc_id}" &>/dev/null; then
        show_success "OIDC provider exists: $oidc_id"
    else
        show_warning "OIDC provider not found: $oidc_id"
        echo "You may need to create it with:"
        echo "eksctl utils associate-iam-oidc-provider --region=${AWS_REGION} --cluster=${CLUSTER_NAME} --approve"
        pause
        return 1
    fi
    
    return 0
}

# Comprehensive IAM verification
verify_all_iam() {
    show_header "Complete IAM Verification" "Verifying all IAM components for Karpenter"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_aws_access || ! check_kubectl_access; then
        return 1
    fi
    
    local verification_results=()
    
    # Run all verifications
    if verify_Karpenter_Node_Role; then
        verification_results+=("✓ Node Role")
    else
        verification_results+=("✗ Node Role")
    fi
    
    if verify_Karpenter_Controller_Role; then
        verification_results+=("✓ Controller Role") 
    else
        verification_results+=("✗ Controller Role")
    fi
    
    if verify_oidc_provider; then
        verification_results+=("✓ OIDC Provider")
    else
        verification_results+=("✗ OIDC Provider")
    fi
    
    if verify_aws; then
        verification_results+=("✓ AWS Auth ConfigMap")
    else
        verification_results+=("✗ AWS Auth ConfigMap")
    fi
    
    if check_service_account_annotations; then
        verification_results+=("✓ Service Account")
    else
        verification_results+=("✗ Service Account")
    fi
    
    # Display results summary
    show_header "Verification Summary" "IAM Verification Results"
    for result in "${verification_results[@]}"; do
        if [[ $result == ✓* ]]; then
            set_green
        else
            set_red
        fi
        echo "$result"
        set_default
    done
    
    # Check if all verifications passed
    if [[ ! " ${verification_results[*]} " =~ " ✗ " ]]; then
        show_success "All IAM verifications passed!"
        return 0
    else
        show_error "Some IAM verifications failed. Please review and fix the issues above."
        return 1
    fi
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_error "This script should be sourced, not executed directly"
    echo "Usage: source iam-verify.sh"
    exit 1
fi
