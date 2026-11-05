# dns-failover

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
| [aws_cloudwatch_metric_alarm.primary_unhealthy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_route53_health_check.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check) | resource |
| [aws_route53_record.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_topic_arn"></a> [alarm\_topic\_arn](#input\_alarm\_topic\_arn) | SNS topic told when the primary is declared unhealthy (a failover is happening). | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The name users type, e.g. app.example.com. It must belong to the hosted zone. | `string` | n/a | yes |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | Path the health checkers request on the primary load balancer. | `string` | `"/health"` | no |
| <a name="input_hosted_zone_id"></a> [hosted\_zone\_id](#input\_hosted\_zone\_id) | ID of the existing Route 53 hosted zone that holds the domain. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the health check and alarm, e.g. webapp-prod. | `string` | n/a | yes |
| <a name="input_primary_alb_dns_name"></a> [primary\_alb\_dns\_name](#input\_primary\_alb\_dns\_name) | DNS name of the primary load balancer. | `string` | n/a | yes |
| <a name="input_primary_alb_zone_id"></a> [primary\_alb\_zone\_id](#input\_primary\_alb\_zone\_id) | Hosted zone ID of the primary load balancer (needed for the alias record). | `string` | n/a | yes |
| <a name="input_secondary_alb_dns_name"></a> [secondary\_alb\_dns\_name](#input\_secondary\_alb\_dns\_name) | DNS name of the DR load balancer. | `string` | n/a | yes |
| <a name="input_secondary_alb_zone_id"></a> [secondary\_alb\_zone\_id](#input\_secondary\_alb\_zone\_id) | Hosted zone ID of the DR load balancer (needed for the alias record). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged onto resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | The name users type. |
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | ID of the Route 53 health check on the primary load balancer. |
<!-- END_TF_DOCS -->
