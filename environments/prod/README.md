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

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Disaster recovery region. Must differ from the primary region. | `string` | `"us-west-2"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. | `string` | `"prod"` | no |
| <a name="input_mock_mode"></a> [mock\_mode](#input\_mock\_mode) | true = fake credentials and no calls to AWS (offline plan). false for a real deployment. | `bool` | `true` | no |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Region that normally serves traffic. | `string` | `"us-east-1"` | no |
| <a name="input_project"></a> [project](#input\_project) | Project name, used in resource names and tags. | `string` | `"webapp"` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
