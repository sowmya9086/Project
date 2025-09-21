#!/bin/bash

# network-setup.sh - Network configuration functions for Karpenter
# This script contains functions to configure and verify network resources for Karpenter

# Source utility functions
NETWORK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${NETWORK_SCRIPT_DIR}/../utils/utils.sh"

# Get and display subnets used by the EKS cluster
get_subnets() {
    show_header "Subnet Information" "Displaying cluster subnets"
    
    echo "Validating subnet tags manually"
    set_blue
    echo "(Looking for karpenter.sh/discovery = ${CLUSTER_NAME})"
    set_default
    
    local subnets
    if subnets=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.subnetIds" --output text 2>/dev/null); then
        echo "Subnets are: $subnets"
        
        for subnet in $subnets; do
            echo "Subnet: $subnet"
            if aws ec2 describe-subnets --subnet-ids "$subnet" --output table --query "Subnets[*].Tags" 2>/dev/null; then
                show_success "Retrieved tags for subnet: $subnet"
            else
                show_error "Could not retrieve tags for subnet: $subnet"
            fi
            echo "---"
        done
    else
        show_error "Could not retrieve subnets for cluster: ${CLUSTER_NAME}"
        return 1
    fi
    
    pause
    return 0
}

# Update subnet tags with Karpenter discovery tags
update_subnets() {
    show_header "Subnet Tag Update" "Adding Karpenter discovery tags to subnets"
    
    echo "Updating tags automatically..."
    echo "(Adding karpenter.sh/discovery = ${CLUSTER_NAME})"
    
    local subnets
    if subnets=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.subnetIds" --output text 2>/dev/null); then
        echo "Subnets are: $subnets"
        
        for subnet in $subnets; do
            echo "Adding Karpenter tags to $subnet"
            
            if aws ec2 create-tags \
                --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
                --resources "$subnet" 2>/dev/null; then
                show_success "Added tags to subnet: $subnet"
            else
                show_error "Failed to add tags to subnet: $subnet"
            fi
        done
        
        show_success "Subnet tagging completed"
    else
        show_error "Could not retrieve subnets for cluster: ${CLUSTER_NAME}"
        return 1
    fi
    
    return 0
}

# Get and display security groups used by the EKS cluster
get_security_groups() {
    show_header "Security Group Information" "Displaying cluster security groups"
    
    echo "Getting security groups and validating tags manually"
    set_blue
    echo "(Looking for karpenter.sh/discovery = ${CLUSTER_NAME})"
    set_default
    
    local security_groups
    if security_groups=$(aws eks describe-cluster \
        --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null); then
        
        echo "Security Groups: $security_groups"
        
        for security_group in $security_groups; do
            echo "Security Group: $security_group"
            if aws ec2 describe-security-groups --group-ids "$security_group" --output table --query "SecurityGroups[*].Tags" 2>/dev/null; then
                show_success "Retrieved tags for security group: $security_group"
            else
                show_error "Could not retrieve tags for security group: $security_group"
            fi
            echo "---"
        done
    else
        show_error "Could not retrieve security groups for cluster: ${CLUSTER_NAME}"
        return 1
    fi
    
    echo "Done looking at security groups"
    pause
    return 0
}

# Update security group tags with Karpenter discovery tags
update_security_groups() {
    show_header "Security Group Tag Update" "Adding Karpenter discovery tags to security groups"
    
    local security_groups
    if security_groups=$(aws eks describe-cluster \
        --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null); then
        
        echo "Security Groups: $security_groups"
        
        for security_group in $security_groups; do
            echo "Updating tags for $security_group"
            
            if aws ec2 create-tags \
                --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
                --resources "$security_group" 2>/dev/null; then
                show_success "Added tags to security group: $security_group"
            else
                show_error "Failed to add tags to security group: $security_group"
            fi
        done
        
        show_success "Security group tagging completed"
    else
        show_error "Could not retrieve security groups for cluster: ${CLUSTER_NAME}"
        return 1
    fi
    
    return 0
}

# Create security group tags (legacy function - use update_security_groups instead)
create_security_group_tags() {
    show_warning "This function is deprecated. Use update_security_groups() instead."
    update_security_groups
}

# Verify network configuration for Karpenter
verify_network_configuration() {
    show_header "Network Configuration Verification" "Checking network setup for Karpenter"
    
    local verification_results=()
    
    # Check if cluster exists and is accessible
    if aws eks describe-cluster --name "${CLUSTER_NAME}" &>/dev/null; then
        show_success "Cluster ${CLUSTER_NAME} is accessible"
        verification_results+=("✓ Cluster Access")
    else
        show_error "Cannot access cluster ${CLUSTER_NAME}"
        verification_results+=("✗ Cluster Access")
        return 1
    fi
    
    # Check subnets
    local subnets
    if subnets=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.subnetIds" --output text 2>/dev/null); then
        local subnet_count=$(echo "$subnets" | wc -w)
        show_success "Found $subnet_count subnets"
        verification_results+=("✓ Subnets ($subnet_count)")
        
        # Check if subnets have Karpenter tags
        local tagged_subnets=0
        for subnet in $subnets; do
            if aws ec2 describe-subnets --subnet-ids "$subnet" --query "Subnets[*].Tags[?Key=='karpenter.sh/discovery' && Value=='${CLUSTER_NAME}']" --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
                ((tagged_subnets++))
            fi
        done
        
        if [[ $tagged_subnets -eq $subnet_count ]]; then
            show_success "All subnets have Karpenter discovery tags"
            verification_results+=("✓ Subnet Tags")
        else
            show_warning "$tagged_subnets/$subnet_count subnets have Karpenter discovery tags"
            verification_results+=("⚠ Subnet Tags ($tagged_subnets/$subnet_count)")
        fi
    else
        show_error "Could not retrieve subnets"
        verification_results+=("✗ Subnets")
    fi
    
    # Check security groups
    local security_groups
    if security_groups=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null); then
        show_success "Found cluster security group"
        verification_results+=("✓ Security Groups")
        
        # Check if security groups have Karpenter tags
        if aws ec2 describe-security-groups --group-ids "$security_groups" --query "SecurityGroups[*].Tags[?Key=='karpenter.sh/discovery' && Value=='${CLUSTER_NAME}']" --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
            show_success "Security group has Karpenter discovery tag"
            verification_results+=("✓ Security Group Tags")
        else
            show_warning "Security group missing Karpenter discovery tag"
            verification_results+=("⚠ Security Group Tags")
        fi
    else
        show_error "Could not retrieve security groups"
        verification_results+=("✗ Security Groups")
    fi
    
    # Display verification summary
    show_header "Network Verification Summary" "Network Configuration Results"
    for result in "${verification_results[@]}"; do
        if [[ $result == ✓* ]]; then
            set_green
        elif [[ $result == ⚠* ]]; then
            set_yellow
        else
            set_red
        fi
        echo "$result"
        set_default
    done
    
    return 0
}

# Configure all network resources for Karpenter
configure_network_for_karpenter() {
    show_header "Complete Network Configuration" "Setting up network resources for Karpenter"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_aws_access; then
        return 1
    fi
    
    show_info "Starting network configuration..."
    
    # Update subnet tags
    if update_subnets; then
        show_success "Subnet configuration completed"
    else
        show_error "Subnet configuration failed"
        return 1
    fi
    
    # Update security group tags
    if update_security_groups; then
        show_success "Security group configuration completed"
    else
        show_error "Security group configuration failed"
        return 1
    fi
    
    # Verify configuration
    verify_network_configuration
    
    show_success "Network configuration for Karpenter completed successfully"
    return 0
}

# Display network information without making changes
show_network_info() {
    show_header "Network Information" "Displaying current network configuration"
    
    echo "Getting network information for cluster: ${CLUSTER_NAME}"
    echo ""
    
    # Show cluster info
    echo "=== Cluster Information ==="
    if aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" --output table 2>/dev/null; then
        show_success "Retrieved cluster information"
    else
        show_error "Could not retrieve cluster information"
    fi
    echo ""
    
    # Show VPC info
    echo "=== VPC Information ==="
    if aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.{VpcId:vpcId,SubnetIds:subnetIds,SecurityGroupIds:securityGroupIds,ClusterSecurityGroupId:clusterSecurityGroupId}" --output table 2>/dev/null; then
        show_success "Retrieved VPC information"
    else
        show_error "Could not retrieve VPC information"
    fi
    echo ""
    
    # Show subnet details
    echo "=== Subnet Details ==="
    get_subnets
    echo ""
    
    # Show security group details  
    echo "=== Security Group Details ==="
    get_security_groups
    
    return 0
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_error "This script should be sourced, not executed directly"
    echo "Usage: source network-setup.sh"
    exit 1
fi
