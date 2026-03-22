# Terraform SRE - Directory Structure

| scope | path | description |
| --- | --- | --- |
| root | README.md | Project overview and architecture |
| root | architecture/ | Architecture diagrams |
| root | app/ | Laravel sample application |
| root | terraform/ | Infrastructure as Code root directory |
| terraform | modules/network | VPC, subnets, NAT |
| terraform | modules/alb | ALB and listeners |
| terraform | modules/ecs | ECS cluster, services, tasks |
| terraform | modules/aurora | Aurora DB module |
| terraform | modules/redis | ElastiCache Redis |
| terraform | modules/sqs | Queue infrastructure |
| terraform | modules/datadog | Monitoring setup |
| terraform | envs/prod/main.tf | Production environment root config |
| terraform | envs/prod/variables.tf | Variables for prod |
| terraform | envs/prod/terraform.tfvars | Environment values |
| terraform | backend.tf | Remote state configuration |
| ci | .github/workflows/terraform.yml | Terraform CI pipeline |
