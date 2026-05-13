module "cpu_ecs_service" {
  source = "../"

  ecs_cluster_name   = var.cluster_name
  ecs_service_name   = "cpu"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  cpu_auto_scaling = {
    enabled            = true
    min_replicas       = 1
    max_replicas       = 5
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
    target_value       = 70
    metric_type        = "ECSServiceAverageCPUUtilization"
  }
}
// 5 resources
