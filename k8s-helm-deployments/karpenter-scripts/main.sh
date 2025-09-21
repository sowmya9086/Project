#!/bin/bash

# main.sh - Main orchestration script for Karpenter automation
# This script provides a unified interface for all Karpenter operations

# Set script directory and source all modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all module scripts
source "${SCRIPT_DIR}/utils/utils.sh"
source "${SCRIPT_DIR}/iam/iam-setup.sh"
source "${SCRIPT_DIR}/iam/iam-verify.sh"
source "${SCRIPT_DIR}/network/network-setup.sh"
source "${SCRIPT_DIR}/deployment/karpenter-deploy.sh"
source "${SCRIPT_DIR}/provisioners/provisioner-management.sh"

# Global configuration variables
export VERIFY_KARPENTER=1
export INSTALL_KARPENTER=1
export REMOVE_KARPENTER=0
export CUSTOM_PROVISIONER=0
export DEBUG=1
export KARPENTER_NAMESPACE=karpenter

# Initialize environment variables
initialize_environment() {
    # Set Karpenter version (can be overridden by environment variable)
    export KARPENTER_VERSION=${KARPENTER_VERSION:-v0.30.0}
    export K8S_VERSION=${K8S_VERSION:-1.27}
    export AWS_PARTITION=${AWS_PARTITION:-aws}
    
    # Auto-detect AWS region if not set
    local get_region
    get_region="$(aws configure list 2>/dev/null | grep region | tr -s " " | cut -d" " -f3)"
    
    if [[ "${get_region}" == "<not" ]] || [[ "${get_region}" == "" ]]; then
        export AWS_DEFAULT_REGION="us-east-1"
    else
        export AWS_DEFAULT_REGION="${get_region}"
    fi
    export AWS_REGION="${AWS_DEFAULT_REGION}"
    
    # Get AWS account ID
    if command -v aws &> /dev/null; then
        export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
    fi
    
    # Auto-detect cluster name from kubectl context
    if command -v kubectl &> /dev/null; then
        local guess_cluster
        guess_cluster=$(kubectl config current-context 2>/dev/null | cut -d/ -f2)
        export CLUSTER_NAME="${CLUSTER_NAME:-$guess_cluster}"
    fi
    
    # Set up OIDC endpoint if cluster name is available
    if [[ -n "$CLUSTER_NAME" ]]; then
        export OIDC_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
            --query "cluster.identity.oidc.issuer" --output text 2>/dev/null)"
        export OIDC_SHORT="$(basename "${OIDC_ENDPOINT}" 2>/dev/null)"
    fi
    
    # Check if Karpenter is already installed
    export KARPENTER_INSTALLED=0
    if kubectl get deployment.apps/karpenter -n karpenter &>/dev/null; then
        export KARPENTER_INSTALLED=1
    fi
    
    # Set department based on cluster name
    if [[ ${CLUSTER_NAME} =~ [Ss][Aa][Ll][Ee][Ss] ]]; then
        export DEPARTMENT='Department: Sales'
    elif [[ ${CLUSTER_NAME} =~ [Ee][Vv][Aa][Ll] ]]; then
        export DEPARTMENT='Department: Sales'
    elif [[ ${CLUSTER_NAME} =~ [Pp][Rr][Oo][Dd] ]]; then
        export DEPARTMENT='Department: Production'
    else 
        export DEPARTMENT=''
    fi
}

# Display help information
get_help() {
    cat << EOF
Karpenter Automation Script

DESCRIPTION:
    This script automates the installation, configuration, and management of 
    Karpenter on Amazon EKS clusters.

USAGE:
    ${0} [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -i, --install           Install and verify Karpenter (default)
    -v, --verify            Verify Karpenter installation only
    -r, --remove            Remove Karpenter from cluster
    -l, --logs              Monitor Karpenter logs
    -p, --provisioner <ns>  Deploy custom provisioners for namespace
    -n, --nodepool          Create NodePools (v1beta1 API)
    -d, --debug             Enable debug mode
    --show-info             Show environment information
    --setup-iam             Set up IAM resources only
    --setup-network         Configure network resources only
    --test                  Run deployment test

ENVIRONMENT VARIABLES:
    KARPENTER_VERSION       Karpenter version to use (default: v0.30.0)
    CLUSTER_NAME           EKS cluster name (auto-detected from context)
    AWS_REGION             AWS region (auto-detected from AWS config)
    AWS_ACCOUNT_ID         AWS account ID (auto-detected)
    KARPENTER_NAMESPACE    Namespace for Karpenter (default: karpenter)

EXAMPLES:
    # Install Karpenter with default settings
    ${0} --install

    # Verify existing Karpenter installation
    ${0} --verify

    # Deploy custom provisioners for a namespace
    ${0} --provisioner myapp

    # Remove Karpenter completely
    ${0} --remove

    # Show environment information
    ${0} --show-info

    # Set up only IAM resources
    ${0} --setup-iam

For more detailed information, see the README.md file.
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                get_help
                exit 0
                ;;
            -i|--install)
                VERIFY_KARPENTER=1
                INSTALL_KARPENTER=1
                REMOVE_KARPENTER=0
                CUSTOM_PROVISIONER=0
                shift
                ;;
            -v|--verify)
                echo "Running verify only mode"
                VERIFY_KARPENTER=1
                INSTALL_KARPENTER=0
                REMOVE_KARPENTER=0
                CUSTOM_PROVISIONER=0
                shift
                ;;
            -r|--remove)
                echo "Running remove karpenter mode"
                VERIFY_KARPENTER=0
                INSTALL_KARPENTER=0
                REMOVE_KARPENTER=1
                CUSTOM_PROVISIONER=0
                shift
                ;;
            -l|--logs)
                echo "Getting logs. Press Ctrl-C to stop"
                get_logs
                exit 0
                ;;
            -p|--provisioner)
                VERIFY_KARPENTER=0
                INSTALL_KARPENTER=0
                REMOVE_KARPENTER=0
                CUSTOM_PROVISIONER=1
                CUSTOM_NAMESPACE="$2"
                
                # Set up customer variables
                if [[ -n "$CUSTOM_NAMESPACE" ]]; then
                    first_letter=$(echo "${CUSTOM_NAMESPACE:0:1}" | tr '[:lower:]' '[:upper:]')
                    rest_of_string="${CUSTOM_NAMESPACE:1}"
                    export CUSTOMER_UPPERCASE="${first_letter}${rest_of_string}"
                    export CUSTOMER_LOWERCASE=$(echo "${CUSTOM_NAMESPACE}" | tr '[:upper:]' '[:lower:]')
                    echo "Deploying custom provisioners for ${CUSTOM_NAMESPACE} for customer ${CUSTOMER_UPPERCASE}"
                else
                    show_error "Namespace required for --provisioner option"
                    exit 1
                fi
                shift 2
                ;;
            -n|--nodepool)
                echo "Creating NodePools (v1beta1 API)"
                create_nodepools
                exit $?
                ;;
            -d|--debug)
                DEBUG=1
                echo "Debug mode enabled"
                shift
                ;;
            --show-info)
                show_environment_info
                exit 0
                ;;
            --setup-iam)
                setup_all_iam_resources
                exit $?
                ;;
            --setup-network)
                configure_network_for_karpenter
                exit $?
                ;;
            --test)
                deployment_test
                exit $?
                ;;
            *)
                show_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Show environment information
show_environment_info() {
    show_header "Environment Information" "Current configuration and status"
    
    echo "=== Karpenter Configuration ==="
    echo "Karpenter Version: ${KARPENTER_VERSION}"
    echo "Namespace: ${KARPENTER_NAMESPACE}"
    echo "Karpenter Installed: $([ "${KARPENTER_INSTALLED:-0}" -eq 1 ] && echo "Yes" || echo "No")"
    echo ""
    
    echo "=== AWS Configuration ==="
    echo "Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo "AWS Partition: ${AWS_PARTITION}"
    echo ""
    
    echo "=== EKS Cluster ==="
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "OIDC Endpoint: ${OIDC_ENDPOINT}"
    echo "Department: ${DEPARTMENT:-Not specified}"
    echo ""
    
    echo "=== Operation Flags ==="
    echo "Install: $([ ${INSTALL_KARPENTER} -eq 1 ] && echo "Yes" || echo "No")"
    echo "Verify: $([ ${VERIFY_KARPENTER} -eq 1 ] && echo "Yes" || echo "No")"
    echo "Remove: $([ ${REMOVE_KARPENTER} -eq 1 ] && echo "Yes" || echo "No")"
    echo "Custom Provisioner: $([ ${CUSTOM_PROVISIONER} -eq 1 ] && echo "Yes (${CUSTOM_NAMESPACE})" || echo "No")"
    echo "Debug: $([ ${DEBUG} -eq 1 ] && echo "Yes" || echo "No")"
    echo ""
    
    # Show tool availability
    echo "=== Tool Availability ==="
    echo "kubectl: $(command -v kubectl > /dev/null && echo "Available" || echo "Missing")"
    echo "aws CLI: $(command -v aws > /dev/null && echo "Available" || echo "Missing")"
    echo "helm: $(command -v helm > /dev/null && echo "Available" || echo "Missing")"
    echo "eksctl: $(command -v eksctl > /dev/null && echo "Available" || echo "Missing")"
    
    # Show access status
    echo ""
    echo "=== Access Status ==="
    if check_kubectl_access &>/dev/null; then
        echo "Kubernetes cluster: Accessible"
    else
        echo "Kubernetes cluster: Not accessible"
    fi
    
    if check_aws_access &>/dev/null; then
        echo "AWS API: Accessible"
    else
        echo "AWS API: Not accessible"
    fi
}

# Main verification function
verify_Karpenter() {
    show_header "Karpenter Verification" "Comprehensive verification of Karpenter installation"
    
    echo "Verifying Karpenter installation..."
    kubectl get all -n karpenter
    pause
    
    echo "Verifying auth configmap..."
    verify_aws
    pause
    
    echo "Verifying subnets..."
    get_subnets
    pause
    
    echo "Verifying security groups..."
    get_security_groups
    pause
    
    echo "Verifying service account..."
    check_service_account_annotations
    pause
    
    echo "Verifying node role..."
    verify_Karpenter_Node_Role
    pause
    
    echo "Verifying controller role..."
    verify_Karpenter_Controller_Role
    pause
    
    echo "Verifying nodes..."
    get_nodes
    pause
    
    show_success "Verification completed"
}

# Main execution flow
main() {
    # Initialize environment
    initialize_environment
    
    # Display debug information if enabled
    if [[ ${DEBUG} -eq 1 ]]; then
        dump_vars
    fi
    
    # Handle removal first
    if [[ ${REMOVE_KARPENTER} -eq 1 ]]; then
        echo "Removing Karpenter. Press Enter to proceed..."
        read -r
        remove_karpenter
        exit $?
    fi
    
    # Handle installation
    if [[ ${INSTALL_KARPENTER} -eq 1 ]]; then
        if [[ ${KARPENTER_INSTALLED} -ne 0 ]]; then
            echo "Karpenter already installed. Verifying only."
            echo "Run with --remove option to remove previous Karpenter installation"
            INSTALL_KARPENTER=0
            VERIFY_KARPENTER=1
        else
            echo "Karpenter not found. Installing..."
            
            # Set up working directory
            mkdir -p ~/karpenter
            pushd ~/karpenter || exit 1
            
            echo "Configuring Karpenter Node Role..."
            setup_Karpenter_Node_Role
            verify_Karpenter_Node_Role
            
            echo "Configuring Karpenter Controller Role..."
            setup_Karpenter_Controller_Role
            pause
            verify_Karpenter_Controller_Role
            
            echo "Configuring linked role (error OK if already done)..."
            create_linked_role
            
            echo "Deploying Karpenter..."
            deploy_Karpenter
            
            echo "Deploying provisioners and AWSNodeTemplates..."
            create_provisioners
            
            echo "Configuring network tags for security groups and subnets..."
            update_security_groups
            update_subnets
            
            echo "Running deployment test..."
            deployment_test
            
            popd || exit 1
        fi
    fi
    
    # Handle verification
    if [[ ${VERIFY_KARPENTER} -eq 1 ]]; then
        verify_Karpenter
    fi
    
    # Handle custom provisioners
    if [[ ${CUSTOM_PROVISIONER} -eq 1 ]]; then
        echo "Deploying custom provisioner for ${CUSTOM_NAMESPACE}"
        create_custom_provisioners
    fi
    
    show_success "Karpenter automation completed successfully"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
else
    # Script is being sourced
    show_info "Karpenter automation modules loaded. Use functions directly or call main script."
    echo "Available main functions:"
    echo "  - setup_all_iam_resources"
    echo "  - deploy_Karpenter"
    echo "  - create_provisioners"
    echo "  - verify_Karpenter"
    echo "  - configure_network_for_karpenter"
    echo "  - show_environment_info"
fi
