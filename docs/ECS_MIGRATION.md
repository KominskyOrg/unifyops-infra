# EC2 to ECS Migration Guide

This document outlines the migration from EC2 instances to Amazon Elastic Container Service (ECS) for the UnifyOps application, with a focus on staying within or minimizing costs beyond the AWS Free Tier.

## Repository Structure

We follow a service-oriented structure where each service owns its own resources:

1. **unifyops-infra**: Contains shared infrastructure components

   - ECS Cluster
   - Task definitions and services
   - IAM roles and policies
   - VPC, security groups, and networking

2. **unifyops-core**: Contains the core service and its specific resources
   - Backend application code
   - ECR repository for container images
   - Deployment workflow
   - Service-specific infrastructure

## Migration Options

We've implemented two approaches for running containers on ECS:

1. **ECS with EC2 Launch Type** (Free Tier Eligible)
2. **ECS with Fargate Launch Type** (Pay-as-you-go with minimal configuration)

## Free Tier Considerations

### ECS with EC2 Launch Type (Free Tier Eligible)

- The ECS service itself is free of charge
- Leverages the AWS Free Tier for EC2 (750 hours of t2.micro/t3.micro per month)
- The container runs on the EC2 instance via the ECS agent
- This option is fully covered by the AWS Free Tier

### ECS with Fargate Launch Type (Pay-as-you-go)

- AWS Fargate has no free tier offering, but costs can be minimized:
  - Use the smallest possible task size (0.25 vCPU, 0.5GB memory)
  - Use Fargate Spot for interruption-tolerant workloads (70% discount)
  - Limit runtime of containers to specific periods
  - Example: Running a minimal container for 10 minutes daily costs approximately $0.60-$0.70/month

## Infrastructure Configuration

The Terraform configuration allows choosing between these options using variables:

| Variable                | Description                                           | Default |
| ----------------------- | ----------------------------------------------------- | ------- |
| `use_ec2_launch_type`   | Whether to use EC2 (true) or Fargate (false)          | `true`  |
| `use_minimal_resources` | Use smallest Fargate resources (0.25 vCPU, 0.5GB RAM) | `true`  |
| `use_fargate_spot`      | Use Fargate Spot for additional cost savings          | `true`  |
| `ecr_repository_url`    | URL of the ECR repository from unifyops-core          | `none`  |

## Deployment Process

1. **Setup the ECR repository in the core service repository**:

   ```bash
   cd unifyops-core/tf
   make init
   make apply
   ```

   Take note of the ECR repository URL from the outputs.

2. **Setup the ECS infrastructure**:

   ```bash
   cd unifyops-infra/tf
   make plan ARGS="-var='ecr_repository_url=<ECR_REPO_URL>'"
   make apply ARGS="-var='ecr_repository_url=<ECR_REPO_URL>'"
   ```

3. **Deploy the core service**:
   The deployment is handled by the GitHub Actions workflow in the core repository.

## Cost Comparison

| Setup                           | Monthly Cost (Est.)         | Free Tier Eligible |
| ------------------------------- | --------------------------- | ------------------ |
| Original EC2 (t2.micro)         | $0 (within free tier)       | Yes                |
| ECS with EC2 (t2.micro)         | $0 (within free tier)       | Yes                |
| ECS with Fargate (minimal)      | ~$1-2 with minimal usage    | No                 |
| ECS with Fargate Spot (minimal) | ~$0.50-1 with minimal usage | No                 |

## Monitoring Costs

Monitor your AWS Billing dashboard regularly, particularly when using Fargate. Set up AWS Budgets to alert you if costs exceed expected thresholds.

## Choosing Between Options

### Use EC2 Launch Type When:

- Staying within free tier is critical
- Your application has consistent, predictable loads
- You can tolerate maintenance overhead for EC2 instances

### Use Fargate When:

- You need simple, hands-off container management
- You prefer to avoid EC2 instance management
- You can tolerate small pay-as-you-go costs
- You need flexible scaling or infrequent execution

## Switching Between Launch Types

To switch from EC2 to Fargate or vice versa, update the `use_ec2_launch_type` variable:

```bash
make apply ARGS="-var='use_ec2_launch_type=false' -var='ecr_repository_url=<ECR_REPO_URL>'"
```

## Migration Steps

1. Set up the ECR repository in the core service repository
2. Apply the ECS infrastructure in the infra repository
3. Deploy your application using the GitHub Actions workflow in the core repository
4. Verify the application is running correctly
5. Once confirmed, you can decommission the original EC2 instance
