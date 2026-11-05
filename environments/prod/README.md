# prod

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.70 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_alb_primary"></a> [alb\_primary](#module\_alb\_primary) | ../../modules/alb | n/a |
| <a name="module_app_primary"></a> [app\_primary](#module\_app\_primary) | ../../modules/ecs-service | n/a |
| <a name="module_ecr_dr"></a> [ecr\_dr](#module\_ecr\_dr) | ../../modules/ecr | n/a |
| <a name="module_ecr_primary"></a> [ecr\_primary](#module\_ecr\_primary) | ../../modules/ecr | n/a |
| <a name="module_monitoring_primary"></a> [monitoring\_primary](#module\_monitoring\_primary) | ../../modules/monitoring | n/a |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | ../../modules/secrets | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../modules/storage | n/a |
| <a name="module_vpc_dr"></a> [vpc\_dr](#module\_vpc\_dr) | ../../modules/vpc | n/a |
| <a name="module_vpc_primary"></a> [vpc\_primary](#module\_vpc\_primary) | ../../modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role_policy.app_primary_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_vpc_security_group_egress_rule.alb_primary_to_app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_iam_policy_document.app_primary_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID. The default is a documentation placeholder so plan works offline. A real deployment sets TF\_VAR\_account\_id. | `string` | `"123456789012"` | no |
| <a name="input_dr_azs"></a> [dr\_azs](#input\_dr\_azs) | Availability zones in the disaster recovery region. | `list(string)` | <pre>[<br/>  "us-west-2a",<br/>  "us-west-2b"<br/>]</pre> | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Disaster recovery region. Must differ from the primary region. | `string` | `"us-west-2"` | no |
| <a name="input_dr_vpc_cidr"></a> [dr\_vpc\_cidr](#input\_dr\_vpc\_cidr) | Address range of the DR VPC. Must be a /16 and must not overlap the primary VPC. | `string` | `"10.20.0.0/16"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. | `string` | `"prod"` | no |
| <a name="input_mock_mode"></a> [mock\_mode](#input\_mock\_mode) | true = fake credentials and no calls to AWS (offline plan). false for a real deployment. | `bool` | `true` | no |
| <a name="input_primary_azs"></a> [primary\_azs](#input\_primary\_azs) | Availability zones in the primary region. Passed in (not looked up) so plan works without AWS credentials. | `list(string)` | <pre>[<br/>  "us-east-1a",<br/>  "us-east-1b"<br/>]</pre> | no |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Region that normally serves traffic. | `string` | `"us-east-1"` | no |
| <a name="input_primary_vpc_cidr"></a> [primary\_vpc\_cidr](#input\_primary\_vpc\_cidr) | Address range of the primary VPC. Must be a /16. | `string` | `"10.10.0.0/16"` | no |
| <a name="input_project"></a> [project](#input\_project) | Project name, used in resource names and tags. | `string` | `"webapp"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_secret_name"></a> [app\_secret\_name](#output\_app\_secret\_name) | Name of the app secret. Set its value out of band before the first deployment. |
| <a name="output_data_bucket_dr"></a> [data\_bucket\_dr](#output\_data\_bucket\_dr) | Name of the replica data bucket in the DR region. |
| <a name="output_data_bucket_primary"></a> [data\_bucket\_primary](#output\_data\_bucket\_primary) | Name of the primary data bucket. |
| <a name="output_dr_vpc_id"></a> [dr\_vpc\_id](#output\_dr\_vpc\_id) | ID of the VPC in the DR region. |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | Where to push the image. Replication copies it to the DR region. |
| <a name="output_primary_alarm_names"></a> [primary\_alarm\_names](#output\_primary\_alarm\_names) | The six alarms for the primary region. |
| <a name="output_primary_alb_dns_name"></a> [primary\_alb\_dns\_name](#output\_primary\_alb\_dns\_name) | DNS name of the primary load balancer. |
| <a name="output_primary_dashboard_name"></a> [primary\_dashboard\_name](#output\_primary\_dashboard\_name) | Name of the CloudWatch dashboard for the primary region. |
| <a name="output_primary_vpc_id"></a> [primary\_vpc\_id](#output\_primary\_vpc\_id) | ID of the VPC in the primary region. |
<!-- END_TF_DOCS -->
