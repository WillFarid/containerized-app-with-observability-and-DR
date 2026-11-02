# prod

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.70 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc_dr"></a> [vpc\_dr](#module\_vpc\_dr) | ../../modules/vpc | n/a |
| <a name="module_vpc_primary"></a> [vpc\_primary](#module\_vpc\_primary) | ../../modules/vpc | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
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
| <a name="output_dr_vpc_id"></a> [dr\_vpc\_id](#output\_dr\_vpc\_id) | ID of the VPC in the DR region. |
| <a name="output_primary_vpc_id"></a> [primary\_vpc\_id](#output\_primary\_vpc\_id) | ID of the VPC in the primary region. |
<!-- END_TF_DOCS -->
