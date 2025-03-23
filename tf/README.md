# UnifyOps Infrastructure

This repository contains the Terraform code for managing the infrastructure for UnifyOps.

## Architecture

The infrastructure is built using AWS services with a focus on:

- **Cost optimization** - Free tier eligible where possible
- **Modularity** - Well-structured code for reuse and maintenance
- **Security** - Following AWS best practices for security

## Project Structure

```
tf/
├── main.tf            # Main entry point with provider configuration
├── variables.tf       # Input variables
├── outputs.tf         # Output values
├── modules/           # Reusable modules
│   ├── ecs/           # ECS cluster module
│   │   ├── main.tf    # Module entry point
│   │   ├── variables.tf # Module variables
│   │   ├── outputs.tf # Module outputs
│   │   ├── cluster.tf # ECS cluster resources
│   │   ├── compute.tf # Launch template and autoscaling
│   │   ├── iam.tf     # IAM roles and policies
│   │   ├── security.tf # Security groups
│   │   └── README.md  # Module documentation
│   └── networking/    # Future networking module
```

## Usage

### Prerequisites

- AWS CLI configured
- Terraform v1.0+ installed
- SSH key pair for EC2 instances (if needed)

### Deployment

1. Initialize Terraform:

   ```bash
   terraform init
   ```

2. Plan the deployment:

   ```bash
   terraform plan -var-file=secrets.tfvars -out=plan.tfplan
   ```

3. Apply the changes:
   ```bash
   terraform apply plan.tfplan
   ```

### Environments

The infrastructure supports multiple environments through variable configuration:

- Development (`dev`)
- Staging (`stage`)
- Production (`prod`)

## Maintenance

### Adding New Resources

1. Identify the appropriate module for the resource
2. Add the resource to the module or create a new module if needed
3. Update the main.tf file to use the new resource
4. Test the changes in a development environment

### Troubleshooting

Common issues:

- ECS cluster inactive: Check EC2 instances and IAM permissions
- Network connectivity issues: Verify security groups and routing
- Instance failures: Review CloudWatch logs at `/var/log/ecs/ecs-agent.log`
