# Karpenter Automation Scripts

A comprehensive, modular script collection for automating Karpenter installation, configuration, and management on Amazon EKS clusters.

## Overview

This project refactors the original monolithic `karpenter_automation.sh` script into a modular, maintainable collection of specialized scripts. Each module handles a specific aspect of Karpenter deployment and management.

## Directory Structure

```
karpenter-scripts/
├── README.md                           # This documentation
├── main.sh                            # Main orchestration script
├── utils/
│   └── utils.sh                       # Common utility functions
├── iam/
│   ├── iam-setup.sh                   # IAM role and policy setup
│   └── iam-verify.sh                  # IAM verification functions
├── network/
│   └── network-setup.sh               # Network configuration (subnets, security groups)
├── deployment/
│   └── karpenter-deploy.sh            # Karpenter deployment functions
└── provisioners/
    └── provisioner-management.sh      # Provisioner and node template management
```

## Prerequisites

Before using these scripts, ensure you have the following tools installed and configured:

### Required Tools
- **kubectl** - Kubernetes command-line tool
- **aws CLI** - AWS command-line interface (configured with appropriate credentials)
- **helm** - Helm package manager for Kubernetes
- **eksctl** - EKS cluster management tool (optional, used for some operations)

### AWS Permissions
Your AWS credentials must have the following permissions:
- EKS cluster management (describe-cluster, etc.)
- IAM role and policy management (create-role, attach-role-policy, etc.)
- EC2 resource management (describe-subnets, describe-security-groups, create-tags, etc.)
- Service-linked role creation for Spot instances

### EKS Cluster
- An existing EKS cluster
- kubectl configured to access the cluster
- OIDC provider associated with the cluster (can be set up automatically)

## Quick Start

### 1. Make Scripts Executable
```bash
chmod +x karpenter-scripts/main.sh
chmod +x karpenter-scripts/*/*.sh
```

### 2. Basic Installation
Install Karpenter with default configuration:
```bash
./karpenter-scripts/main.sh --install
```

### 3. Verify Installation
Check existing Karpenter installation:
```bash
./karpenter-scripts/main.sh --verify
```

### 4. Show Environment Information
Display current configuration and status:
```bash
./karpenter-scripts/main.sh --show-info
```

## Usage

### Main Script Options

```bash
./main.sh [OPTIONS]

OPTIONS:
    -h, --help              Show help message
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
```

### Environment Variables

You can customize behavior using these environment variables:

```bash
export KARPENTER_VERSION=v0.33.1         # Karpenter version (fixed at v0.33.1)
export CLUSTER_NAME=my-eks-cluster       # EKS cluster name
export AWS_REGION=us-west-2              # AWS region
export KARPENTER_NAMESPACE=karpenter     # Namespace for Karpenter
```

### Common Usage Examples

#### Install Karpenter
```bash
# Default installation (uses v0.33.1)
./main.sh --install

# Install with debug output
./main.sh --install --debug
```

#### Verify Installation
```bash
# Quick verification
./main.sh --verify

# Show detailed environment info
./main.sh --show-info
```

#### Custom Provisioners
```bash
# Deploy custom provisioners for a specific namespace
./main.sh --provisioner myapp

# This creates provisioners named:
# - myapp-karpenter (general purpose)
# - myapp-storage (high storage)
# - bas-myapp (BAS workloads)
```

#### NodePools (v1beta1 API)
```bash
# Create NodePools for newer Karpenter versions
./main.sh --nodepool
```

#### Individual Operations
```bash
# Set up only IAM resources
./main.sh --setup-iam

# Configure only network resources
./main.sh --setup-network

# Run deployment test
./main.sh --test

# Monitor logs
./main.sh --logs
```

#### Removal
```bash
# Remove Karpenter (prompts for confirmation)
./main.sh --remove
```

## Module Documentation

### utils/utils.sh
Common utility functions used across all modules:
- Color output functions (`set_green`, `set_red`, etc.)
- User interaction (`pause`, `show_header`)
- Environment validation (`validate_environment`, `check_kubectl_access`)
- Logging and status functions (`show_success`, `show_error`, etc.)

### iam/iam-setup.sh
IAM resource setup functions:
- `setup_Karpenter_Node_Role()` - Creates node IAM role with required policies
- `setup_Karpenter_Controller_Role()` - Creates controller IAM role
- `create_linked_role()` - Creates service-linked role for Spot instances
- `setup_all_iam_resources()` - Complete IAM setup

### iam/iam-verify.sh
IAM verification functions:
- `verify_Karpenter_Node_Role()` - Validates node role configuration
- `verify_Karpenter_Controller_Role()` - Validates controller role
- `check_service_account_annotations()` - Verifies service account setup
- `verify_all_iam()` - Comprehensive IAM verification

### network/network-setup.sh
Network configuration functions:
- `get_subnets()` - Display cluster subnets and their tags
- `update_subnets()` - Add Karpenter discovery tags to subnets
- `get_security_groups()` - Display security groups and tags
- `update_security_groups()` - Add Karpenter discovery tags
- `configure_network_for_karpenter()` - Complete network setup

### deployment/karpenter-deploy.sh
Karpenter deployment functions:
- `create_crds()` - Deploy Karpenter Custom Resource Definitions
- `deploy_Karpenter()` - Deploy Karpenter controller to cluster
- `remove_karpenter()` - Remove Karpenter from cluster
- `verify_karpenter_deployment()` - Verify deployment status

### provisioners/provisioner-management.sh
Provisioner and node template management:
- `create_provisioners()` - Create standard provisioners (default, storage, BAS)
- `create_custom_provisioners()` - Create namespace-specific provisioners
- `create_nodepools()` - Create NodePools for v1beta1 API
- `verify_provisioners()` - Display current provisioners
- `remove_provisioners()` - Remove all provisioners

## Supported Karpenter Version

The scripts are designed specifically for Karpenter v0.33.1:

### v0.33.1 (Current)
- Uses v1beta1 NodePool API
- Uses v1beta1 EC2NodeClass API  
- Uses v1beta1 NodeClaim API
- Simplified configuration without instance profile setting
- Modern resource management with improved scaling and provisioning

## Provisioner Types

The scripts create three types of provisioners by default:

### 1. defaultkarpenter
- **Purpose**: General-purpose workloads
- **Instance Types**: m5.medium to m5.4xlarge
- **Capacity**: On-demand
- **Storage**: 50GB GP3 root volume

### 2. karpenter_storage
- **Purpose**: Storage-intensive workloads
- **Instance Types**: m5.medium to m5.4xlarge
- **Capacity**: On-demand
- **Storage**: 300GB root + 200GB data volume

### 3. bas-karpenter
- **Purpose**: BAS (Business Application Services) workloads
- **Instance Types**: m6+ generations or choose any type
- **Capacity**: On-demand, Spot
- **Storage**: 250GB root + 250GB data volume

### Custom Provisioners
When using `--provisioner <namespace>`, three namespace-specific provisioners are created:
- `<namespace>-karpenter` (general purpose)
- `<namespace>-storage` (high storage)
- `bas-<namespace>` (BAS workloads)

## Troubleshooting

### Common Issues

#### 1. kubectl Context Issues
```bash
# Check current context
kubectl config current-context

# Set correct context
kubectl config use-context arn:aws:eks:region:account:cluster/cluster-name
```

#### 2. AWS Credentials
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check region configuration
aws configure list
```

#### 3. Cluster Access
```bash
# Test cluster access
kubectl get nodes

# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name my-cluster
```

#### 4. IAM Permissions
If you encounter IAM permission errors, ensure your AWS credentials have the necessary permissions listed in the Prerequisites section.

#### 5. OIDC Provider Issues
```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# Create OIDC provider if missing
eksctl utils associate-iam-oidc-provider --cluster=my-cluster --approve
```

### Debug Mode
Enable debug mode for detailed output:
```bash
./main.sh --install --debug
```

### Verification Steps
Run comprehensive verification:
```bash
./main.sh --verify
```

Check individual components:
```bash
./main.sh --show-info  # Show environment
kubectl get all -n karpenter  # Check deployments
kubectl get nodepools  # Check NodePools (v1beta1)
kubectl get ec2nodeclasses  # Check EC2NodeClasses (v1beta1)
kubectl get nodes  # Check nodes
```

## Migration from Original Script

If you're migrating from the original `karpenter_automation.sh`:

### 1. Backup Existing Setup
```bash
# Backup current configuration files
cp ~/karpenter/*.yaml ~/karpenter/backup/
```

### 2. Use Equivalent Commands
| Original | New Script |
|----------|------------|
| `./karpenter_automation.sh` | `./main.sh --install` |
| `./karpenter_automation.sh v` | `./main.sh --verify` |
| `./karpenter_automation.sh r` | `./main.sh --remove` |
| `./karpenter_automation.sh l` | `./main.sh --logs` |
| `./karpenter_automation.sh p namespace` | `./main.sh --provisioner namespace` |

### 3. Environment Variables
The new scripts use the same environment variables as the original script, so your existing configuration should work.

## Advanced Usage

### Using Individual Modules

You can source individual modules and use their functions directly:

```bash
# Source specific modules
source karpenter-scripts/utils/utils.sh
source karpenter-scripts/iam/iam-setup.sh

# Use functions directly
setup_Karpenter_Node_Role
verify_Karpenter_Node_Role
```

### Custom Configurations

#### Custom Namespace
```bash
KARPENTER_NAMESPACE=my-karpenter ./main.sh --install
```

#### Custom Working Directory
The scripts create a working directory at `~/karpenter` where they store generated files like Helm templates and YAML configurations.

## Contributing

When modifying these scripts:

1. **Follow the modular structure** - Keep functions in their appropriate modules
2. **Use utility functions** - Leverage the common utilities in `utils.sh`
3. **Add error handling** - Check return codes and provide meaningful error messages
4. **Update documentation** - Keep this README current with any changes
5. **Test thoroughly** - Test both installation and removal scenarios

## License

This project maintains the same license as the original script. Please refer to your organization's licensing terms.

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Run with `--debug` flag for detailed output
3. Use `--show-info` to verify your environment
4. Consult the AWS EKS and Karpenter documentation

## Files Generated

The scripts generate several files during execution:

- `~/karpenter/<cluster-name>_karpenter.yaml` - Helm template for Karpenter
- `*.yaml` files for provisioners and node templates
- Temporary policy files (cleaned up automatically)

These files are preserved for troubleshooting and future reference.
