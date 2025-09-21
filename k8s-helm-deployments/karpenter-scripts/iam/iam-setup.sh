#!/bin/bash

# iam-setup.sh - IAM setup functions for Karpenter
# This script contains functions to set up IAM roles and policies required for Karpenter

# Source utility functions
IAM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${IAM_SCRIPT_DIR}/../utils/utils.sh"

# Set up Karpenter Node Role
setup_Karpenter_Node_Role() {
    show_header "IAM Node Role Setup" "Setting up Karpenter Node Role"
    
    echo "Setting up Karpenter Node Role: KarpenterNodeRole-${CLUSTER_NAME}"
    
    # Create trust policy for EC2
    echo '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' > node-trust-policy.json

    # Create the IAM role
    if aws iam create-role --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
        --assume-role-policy-document file://node-trust-policy.json; then
        show_success "Created KarpenterNodeRole-${CLUSTER_NAME}"
    else
        show_warning "Role may already exist, continuing..."
    fi

    # Attach required AWS managed policies
    local policies=(
        "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEKS_CNI_Policy"
        "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        "arn:${AWS_PARTITION}:iam::aws:policy/AmazonSSMManagedInstanceCore"
    )

    for policy in "${policies[@]}"; do
        if aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
            --policy-arn "$policy"; then
            show_success "Attached policy: $(basename $policy)"
        else
            show_warning "Policy $(basename $policy) may already be attached"
        fi
    done

    # Create instance profile
    if aws iam create-instance-profile \
         --instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}"; then
        show_success "Created instance profile: KarpenterNodeInstanceProfile-${CLUSTER_NAME}"
    else
        show_warning "Instance profile may already exist"
    fi

    # Add role to instance profile
    if aws iam add-role-to-instance-profile \
         --instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}" \
        --role-name "KarpenterNodeRole-${CLUSTER_NAME}"; then
        show_success "Added role to instance profile"
    else
        show_warning "Role may already be added to instance profile"
    fi

    # Cleanup temporary files
    rm -f node-trust-policy.json
}

# Create controller policy file
create_controller_policy_file() {
    show_info "Creating controller policy file"
    
cat << EOF > controller-policy.json
{
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeAvailabilityZones",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/provisioner-name": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:${AWS_PARTITION}:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}",
            "Sid": "EKSClusterEndpointLookup"
        }
    ],
    "Version": "2012-10-17"
}
EOF
}

# Create controller trust policy file
create_controller_trust_policy_file() {
    show_info "Creating controller trust policy file"
    
     cat << EOF > controller-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT#*//}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_ENDPOINT#*//}:aud": "sts.amazonaws.com",
                    "${OIDC_ENDPOINT#*//}:sub": "system:serviceaccount:${KARPENTER_NAMESPACE}:karpenter"
                }
            }
        }
    ]
}
EOF
}

# Set up Karpenter Controller Role
setup_Karpenter_Controller_Role() {
    show_header "IAM Controller Role Setup" "Setting up Karpenter Controller Role"
    
    echo "Setting up KarpenterControllerRole-${CLUSTER_NAME}"
    
    # Create trust policy file
    create_controller_trust_policy_file

    # Create the controller role
    if aws iam create-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
        --assume-role-policy-document file://controller-trust-policy.json; then
        show_success "Created KarpenterControllerRole-${CLUSTER_NAME}"
    else
        show_warning "Controller role may already exist"
    fi
    
    # Create and attach the controller policy
    create_controller_policy_file
    
    if aws iam put-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
        --policy-name "KarpenterControllerPolicy-${CLUSTER_NAME}" \
        --policy-document file://controller-policy.json; then
        show_success "Attached controller policy"
    else
        show_warning "Controller policy may already be attached"
    fi

    # Cleanup temporary files
    rm -f controller-trust-policy.json controller-policy.json
}

# Create service linked role for Spot instances
create_linked_role() {
    show_header "Service Linked Role" "Creating service linked role for Spot instances"
    
    echo "Creating service linked role (OK to error if already exists)"
    if aws iam create-service-linked-role --aws-service-name spot.amazonaws.com; then
        show_success "Created service linked role for spot.amazonaws.com"
    else
        show_info "Service linked role already exists or creation failed (this is often OK)"
    fi
}

# Set up CloudFormation IAM resources (legacy method)
setup_cloudformation_iam_stuff() {
    show_header "CloudFormation IAM Setup" "Setting up IAM resources via CloudFormation"
    show_warning "This is a legacy method - consider using individual IAM setup functions instead"
    
    # Download CloudFormation template
    local cf_template="karpenter-cloudformation.yaml"
    if curl -fsSL "https://karpenter.sh/${KARPENTER_VERSION}/getting-started/getting-started-with-eksctl/cloudformation.yaml" > "$cf_template"; then
        show_success "Downloaded CloudFormation template"
    else
        show_error "Failed to download CloudFormation template"
        return 1
    fi
    
    # Deploy CloudFormation stack
    if aws cloudformation deploy \
        --stack-name "Karpenter-${CLUSTER_NAME}" \
        --template-file "$cf_template" \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides "ClusterName=${CLUSTER_NAME}"; then
        show_success "Deployed CloudFormation stack: Karpenter-${CLUSTER_NAME}"
    else
        show_error "Failed to deploy CloudFormation stack"
        return 1
    fi
    
    # Create IAM identity mapping
    if eksctl create iamidentitymapping \
        --username system:node:{{EC2PrivateDNSName}} \
        --cluster "${CLUSTER_NAME}" \
        --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
        --group system:bootstrappers \
        --group system:nodes; then
        show_success "Created IAM identity mapping"
    else
        show_warning "IAM identity mapping may already exist"
    fi
    
    # Create IAM service account
    if eksctl create iamserviceaccount \
        --cluster "${CLUSTER_NAME}" \
        --name karpenter \
        --namespace karpenter \
        --role-name "${CLUSTER_NAME}-karpenter" \
        --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
        --role-only \
        --approve; then
        show_success "Created IAM service account"
    else
        show_warning "IAM service account may already exist"
    fi
    
    # Cleanup
    rm -f "$cf_template"
}

# Main function to set up all IAM resources
setup_all_iam_resources() {
    show_header "Complete IAM Setup" "Setting up all required IAM resources for Karpenter"
    
    # Validate environment
    if ! validate_environment; then
        return 1
    fi
    
    if ! check_aws_access; then
        return 1
    fi
    
    # Set up all IAM components
    setup_Karpenter_Node_Role
    setup_Karpenter_Controller_Role  
    create_linked_role
    
    show_success "All IAM resources have been set up successfully"
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_error "This script should be sourced, not executed directly"
    echo "Usage: source iam-setup.sh"
    exit 1
fi
