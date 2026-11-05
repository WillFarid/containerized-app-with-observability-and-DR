# ecs-service

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.70 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.70 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution_read_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.app_https_out](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.app_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.ecs_tasks_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.read_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID. Used to build the exact ARN pattern of the secret. | `string` | n/a | yes |
| <a name="input_alb_sg_id"></a> [alb\_sg\_id](#input\_alb\_sg\_id) | Security group of the load balancer. It is the only source allowed to reach the tasks. | `string` | n/a | yes |
| <a name="input_app_port"></a> [app\_port](#input\_app\_port) | Port the app listens on. | `number` | `8080` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units (256 = 0.25 vCPU). | `number` | `256` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Starting number of tasks. Autoscaling adjusts it afterwards. | `number` | `2` | no |
| <a name="input_image"></a> [image](#input\_image) | Full image reference including a version tag, e.g. <repository-url>:1.0.0. Never use latest. | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | How long to keep container logs in CloudWatch. | `number` | `365` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory in MiB. Must be a valid pair with cpu. | `number` | `512` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources, e.g. webapp-prod-primary. IAM is global, so it must be unique per copy. | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnets (one per AZ) where tasks run. | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region this copy runs in. Used for log settings and reported by the app. | `string` | n/a | yes |
| <a name="input_secret_kms_key_arn"></a> [secret\_kms\_key\_arn](#input\_secret\_kms\_key\_arn) | ARN of the customer-managed key that encrypts the secret. null when the secret uses the AWS-managed key (as the DR replica does). | `string` | `null` | no |
| <a name="input_secret_name"></a> [secret\_name](#input\_secret\_name) | Name of the Secrets Manager secret injected into the container as APP\_SECRET. It must exist in this region. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged onto resources. | `map(string)` | `{}` | no |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | Load balancer target group the service registers tasks with. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the tasks run in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the ECS cluster. |
| <a name="output_execution_role_name"></a> [execution\_role\_name](#output\_execution\_role\_name) | Name of the role ECS uses to start tasks. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the container log group. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group of the tasks. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service (used by autoscaling and monitoring). |
| <a name="output_task_role_name"></a> [task\_role\_name](#output\_task\_role\_name) | Name of the app's runtime role. Later steps attach narrow permissions to it. |
<!-- END_TF_DOCS -->
