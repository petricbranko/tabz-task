# redis

ElastiCache for Redis OSS replication group (cluster mode disabled) plus the Secrets Manager secret the
application reads. Composes the official
[`terraform-aws-modules/elasticache`](https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws/latest) and
[`terraform-aws-modules/secrets-manager`](https://registry.terraform.io/modules/terraform-aws-modules/secrets-manager/aws/latest) modules.

- TLS in transit (`transit_encryption_mode = "required"`), at-rest encryption with a CMK, AUTH token.
- `num_cache_clusters > 1` automatically turns on automatic failover + Multi-AZ.
- The security group is created **without ingress**. Consumers add their own SG-referenced rule
  (`modules/ecs-service` does this through `downstream_security_groups`), so the cache never trusts a CIDR.
- Secret JSON: `{"host", "reader", "port", "tls", "auth_token"}`. ECS injects single keys with
  `valueFrom = "<secret_arn>:auth_token::"`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.41, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6, < 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6, < 4.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_redis"></a> [redis](#module\_redis) | terraform-aws-modules/elasticache/aws | 1.11.2 |
| <a name="module_secret"></a> [secret](#module\_secret) | terraform-aws-modules/secrets-manager/aws | 2.2.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [random_password.auth_token](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications immediately instead of during the maintenance window | `bool` | `false` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Redis OSS engine version | `string` | `"7.1"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key used for at-rest encryption of the cache and the secret | `string` | n/a | yes |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention for the slow-log CloudWatch log group | `number` | `14` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Weekly maintenance window (UTC) | `string` | `"sun:03:00-sun:04:00"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the replication group; also used as prefix for the secret and security group | `string` | n/a | yes |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | Cache node instance type | `string` | n/a | yes |
| <a name="input_num_cache_clusters"></a> [num\_cache\_clusters](#input\_num\_cache\_clusters) | Number of nodes (1 primary + N-1 replicas). > 1 enables automatic failover and Multi-AZ | `number` | `1` | no |
| <a name="input_parameter_group_family"></a> [parameter\_group\_family](#input\_parameter\_group\_family) | Parameter group family matching engine\_version | `string` | `"redis7"` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Parameter overrides for the parameter group | `list(map(string))` | `[]` | no |
| <a name="input_port"></a> [port](#input\_port) | Port Redis listens on | `number` | `6379` | no |
| <a name="input_secret_recovery_window_in_days"></a> [secret\_recovery\_window\_in\_days](#input\_secret\_recovery\_window\_in\_days) | Recovery window for the secret; 0 forces immediate deletion (only sensible for ephemeral envs) | `number` | `30` | no |
| <a name="input_snapshot_retention_limit"></a> [snapshot\_retention\_limit](#input\_snapshot\_retention\_limit) | Days to keep automatic snapshots (0 disables snapshots) | `number` | `0` | no |
| <a name="input_snapshot_window"></a> [snapshot\_window](#input\_snapshot\_window) | Daily snapshot window (UTC); must not overlap the maintenance window | `string` | `"01:00-02:00"` | no |
| <a name="input_subnet_group_name"></a> [subnet\_group\_name](#input\_subnet\_group\_name) | Existing ElastiCache subnet group (created by the VPC module from the data subnets) | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (provider default\_tags already cover the standard set) | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the replication group lives in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_port"></a> [port](#output\_port) | Redis port |
| <a name="output_primary_endpoint_address"></a> [primary\_endpoint\_address](#output\_primary\_endpoint\_address) | Primary (read/write) endpoint; follows the primary on failover |
| <a name="output_reader_endpoint_address"></a> [reader\_endpoint\_address](#output\_reader\_endpoint\_address) | Reader endpoint load balancing across replicas |
| <a name="output_replication_group_id"></a> [replication\_group\_id](#output\_replication\_group\_id) | ID of the replication group |
| <a name="output_secret_arn"></a> [secret\_arn](#output\_secret\_arn) | ARN of the Secrets Manager secret holding host/port/auth\_token |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group attached to the cache nodes. Consumers add ingress rules to it |
<!-- END_TF_DOCS -->
