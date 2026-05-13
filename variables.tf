variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 7
}

variable "application_load_balancer" {
  description = "alb"
  type = object({
    enabled                          = optional(bool, false)
    container_port                   = optional(number, 80)
    listener_arn                     = optional(string, "")
    nlb_arn                          = optional(string, "")
    nlb_port                         = optional(number, 80)
    host                             = optional(string, "")
    path                             = optional(string, "/*")
    protocol                         = optional(string, "HTTP")
    health_check_path                = optional(string, "/health")
    health_check_matcher             = optional(string, "200")
    health_check_interval_sec        = optional(number, 30)
    health_check_timeout_sec         = optional(number, 10)
    health_check_threshold_healthy   = optional(number, 2)
    health_check_threshold_unhealthy = optional(number, 5)
    health_check_protocol            = optional(string, "HTTP")
    health_check_port                = optional(string, "traffic-port")
    stickiness                       = optional(bool, false)
    stickiness_ttl                   = optional(number, 300)
    cookie_name                      = optional(string, "")
    stickiness_type                  = optional(string, "app_cookie")
    action_type                      = optional(string, "forward")
    target_group_name                = optional(string, "")
    deregister_deregistration_delay  = optional(number, 60)
    route_53_host_zone_id            = optional(string, "")
    cloudflare_zone_id               = optional(string, "")
    cloudflare_proxied               = optional(bool, true)
    cloudflare_ttl                   = optional(number, 300)
  })
  default = {}
}

variable "additional_load_balancers" {
  description = "Additional load balancers configuration"
  type = list(object({
    enabled                          = optional(bool, false)
    container_port                   = optional(number, 80)
    listener_arn                     = optional(string, "")
    nlb_arn                          = optional(string, "")
    nlb_port                         = optional(number, 80)
    host                             = optional(string, "")
    path                             = optional(string, "/*")
    protocol                         = optional(string, "HTTP")
    health_check_path                = optional(string, "/health")
    health_check_matcher             = optional(string, "200")
    health_check_interval_sec        = optional(number, 30)
    health_check_timeout_sec         = optional(number, 10)
    health_check_threshold_healthy   = optional(number, 2)
    health_check_threshold_unhealthy = optional(number, 5)
    health_check_protocol            = optional(string, "HTTP")
    health_check_port                = optional(string, "traffic-port")
    stickiness                       = optional(bool, false)
    stickiness_ttl                   = optional(number, 300)
    stickiness_type                  = optional(string, "app_cookie")
    cookie_name                      = optional(string, "")
    action_type                      = optional(string, "forward")
    target_group_name                = optional(string, "")
    deregister_deregistration_delay  = optional(number, 60)
    route_53_host_zone_id            = optional(string, "")
    cloudflare_zone_id               = optional(string, "")
    cloudflare_proxied               = optional(bool, true)
    cloudflare_ttl                   = optional(number, 300)
  }))
  default = []
}





variable "service_connect" {
  type = object({
    enabled     = optional(bool, false)
    type        = optional(string, "client-only")
    port        = optional(number, 80)
    name        = optional(string, "service")
    timeout     = optional(number, 15)
    appProtocol = optional(string, "http")
    additional_ports = optional(list(object({
      name        = string
      port        = number
      appProtocol = optional(string, "http")
    })), [])
  })

  default = {}

  validation {
    condition     = contains(["client-only", "client-server"], var.service_connect.type)
    error_message = "Allowed values for service_connect.type are: client-only, client-server."
  }

  validation {
    condition     = var.service_connect.enabled == false || contains(["http", "tcp"], var.service_connect.appProtocol)
    error_message = "Allowed values for service_connect.appProtocol are: http, tcp."
  }
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}
variable "security_group_ids" {
  description = "Security group IDs for the ECS tasks. Required when network_mode is 'awsvpc'."
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "Subnet IDs for the ECS tasks. Required when network_mode is 'awsvpc'."
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks"
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Enable execute command"
  type        = bool
  default     = false
}

variable "ecs_task_cpu" {
  description = "CPU units for the ECS task"
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory for the ECS task in MiB"
  type        = number
  default     = 512
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "nginx:latest"
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}


variable "ecs_launch_type" {
  description = "Launch type for the ECS service (FARGATE or EC2)"
  type        = string
  default     = "FARGATE"
  validation {
    condition     = contains(["FARGATE", "EC2"], var.ecs_launch_type)
    error_message = "Valid values for ecs_launch_type are FARGATE or EC2."
  }
}

variable "network_mode" {
  description = "Network mode for the ECS task definition. Fargate requires 'awsvpc'. EC2 supports 'awsvpc', 'bridge', 'host', or 'none'."
  type        = string
  default     = "awsvpc"

  validation {
    condition     = contains(["awsvpc", "bridge", "host", "none"], var.network_mode)
    error_message = "Valid values for network_mode are: awsvpc, bridge, host, none."
  }
}
variable "deployment" {
  description = "Deployment configuration for the ECS service"
  type = object({
    min_healthy_percent       = optional(number, 100)
    max_healthy_percent       = optional(number, 200)
    circuit_breaker_enabled   = optional(bool, true)
    rollback_enabled          = optional(bool, true)
    cloudwatch_alarm_enabled  = optional(bool, false)
    cloudwatch_alarm_rollback = optional(bool, true)
    cloudwatch_alarm_names    = optional(list(string), [])
  })
  default = {}

}
variable "capacity_provider_strategy" {
  description = "name of the capacity"
  type        = string
  default     = ""
}

variable "cpu_auto_scaling" {
  description = "value for auto scaling"
  default     = {}
  type = object({
    enabled            = optional(bool, false)
    min_replicas       = optional(number, 0)
    max_replicas       = optional(number, 1)
    scale_in_cooldown  = optional(number, 300)
    scale_out_cooldown = optional(number, 300)
    target_value       = optional(number, 70)
    metric_type        = optional(string, "ECSServiceAverageCPUUtilization")
  })
}

variable "memory_auto_scaling" {
  description = "value for auto scaling"
  default     = {}
  type = object({
    enabled            = optional(bool, false)
    min_replicas       = optional(number, 0)
    max_replicas       = optional(number, 1)
    scale_in_cooldown  = optional(number, 300)
    scale_out_cooldown = optional(number, 300)
    target_value       = optional(number, 70)

  })
}
variable "sqs_autoscaling" {
  description = "Opinionated SQS autoscaling config for this ECS service."
  default     = {}
  type = object({
    enabled = optional(bool, false)

    # Queue names — either set queue_name for both directions, or set each explicitly
    queue_name           = optional(string)
    scale_out_queue_name = optional(string)
    scale_in_queue_name  = optional(string)

    # Capacity guardrails (required when enabled)
    min_replicas = optional(number)
    max_replicas = optional(number)

    # SLA thresholds for AgeOfOldestMessage (seconds)
    scale_out_age_seconds = optional(number)
    scale_in_age_seconds  = optional(number)

    # Scale-in behavior (defaults baked in)
    # If true, requires queue to be completely empty before scaling in (more stable)
    # If false (default), scales in based on age alone (more cost-efficient)
    require_empty_for_scale_in = optional(bool)
    empty_eval_periods         = optional(number)
    empty_period_seconds       = optional(number)

    # Step ladders (scale-out proportional)
    scale_out_steps = optional(list(object({
      lower  = number
      upper  = optional(number)
      change = number
    })))

    # Scale-in step size (gentle shrink)
    scale_in_step = optional(number)

    # Cooldowns (override if needed)
    scale_out_cooldown = optional(number)
    scale_in_cooldown  = optional(number)

    # Smoothing for Age via metric math (simple SMA on 60s periods). 0 disables.
    age_sma_points = optional(number)

    # Aggregation & missing data behavior
    aggregation_type_out = optional(string)
    aggregation_type_in  = optional(string)
    treat_missing_out    = optional(string)
    treat_missing_in     = optional(string)
  })

  validation {
    condition = !var.sqs_autoscaling.enabled || try(
      var.sqs_autoscaling.max_replicas != null &&
      var.sqs_autoscaling.min_replicas != null &&
      var.sqs_autoscaling.max_replicas >= var.sqs_autoscaling.min_replicas &&
      var.sqs_autoscaling.min_replicas >= 0,
      false
    )
    error_message = "When sqs_autoscaling is enabled, min_replicas and max_replicas must be set, with max_replicas >= min_replicas >= 0."
  }

  validation {
    condition = !var.sqs_autoscaling.enabled || (
      var.sqs_autoscaling.queue_name != null ||
      (var.sqs_autoscaling.scale_out_queue_name != null && var.sqs_autoscaling.scale_in_queue_name != null)
    )
    error_message = "When sqs_autoscaling is enabled, either queue_name or both scale_out_queue_name and scale_in_queue_name must be provided."
  }

  validation {
    condition = !var.sqs_autoscaling.enabled || try(
      var.sqs_autoscaling.scale_out_age_seconds != null &&
      var.sqs_autoscaling.scale_in_age_seconds != null &&
      var.sqs_autoscaling.scale_out_age_seconds > var.sqs_autoscaling.scale_in_age_seconds &&
      var.sqs_autoscaling.scale_in_age_seconds >= 0,
      false
    )
    error_message = "When sqs_autoscaling is enabled, scale_out_age_seconds and scale_in_age_seconds must be set, with scale_out_age_seconds > scale_in_age_seconds >= 0."
  }

  validation {
    condition = (
      !var.sqs_autoscaling.enabled ||
      var.sqs_autoscaling.scale_out_steps == null ||
      try(alltrue([for s in var.sqs_autoscaling.scale_out_steps : s.change > 0]), true)
    )
    error_message = "All scale_out_steps must have change > 0."
  }
}

variable "schedule_auto_scaling" {
  description = "Scheduled auto scaling configuration"
  default     = {}
  type = object({
    enabled = optional(bool, false)
    schedules = optional(list(object({
      schedule_name       = optional(string, "")
      min_replicas        = optional(number, 0)
      max_replicas        = optional(number, 1)
      schedule_expression = optional(string, "cron(0 0 1 * ? *)") # cron expression
      time_zone           = optional(string, "Asia/Jerusalem")
    })), [])
  })
}

variable "ecr" {
  description = "ECR repository configuration"
  type = object({
    create_repo         = optional(bool, false)
    repo_name           = optional(string, "")
    mutability          = optional(string, "MUTABLE")
    untagged_ttl_days   = optional(number, 7)
    tagged_ttl_days     = optional(number, 7)
    protected_prefixes  = optional(list(string), ["main", "master"])
    protected_retention = optional(number, 999999) # Keep nearly forever
    versioned_prefixes  = optional(list(string), ["v", "sha"])
    versioned_retention = optional(number, 30) # How many versioned tags to keep
  })
  default = {}
}

variable "log_anomaly_detection" {
  description = "CloudWatch Logs Anomaly Detection configuration"
  type = object({
    enabled                 = optional(bool, false)
    evaluation_frequency    = optional(string, "TEN_MIN")
    anomaly_visibility_time = optional(number, 7)
    filter_pattern          = optional(string, "")
  })
  default = {}

  validation {
    condition = contains(
      ["ONE_MIN", "FIVE_MIN", "TEN_MIN", "FIFTEEN_MIN", "THIRTY_MIN", "ONE_HOUR"],
      var.log_anomaly_detection.evaluation_frequency
    )
    error_message = "evaluation_frequency must be one of: ONE_MIN, FIVE_MIN, TEN_MIN, FIFTEEN_MIN, THIRTY_MIN, ONE_HOUR"
  }

  validation {
    condition     = var.log_anomaly_detection.anomaly_visibility_time >= 7 && var.log_anomaly_detection.anomaly_visibility_time <= 90
    error_message = "anomaly_visibility_time must be between 7 and 90 days"
  }
}

variable "placement_strategy" {
  description = "Ordered placement strategy for ECS service (only applicable for EC2 launch type). Type can be binpack, spread, or random."
  type = list(object({
    type  = string
    field = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.placement_strategy : contains(["binpack", "spread", "random"], s.type)])
    error_message = "placement_strategy type must be one of: binpack, spread, random"
  }
}

variable "placement_constraints" {
  description = "Placement constraints for ECS service (only applicable for EC2 launch type). Type can be distinctInstance or memberOf."
  type = list(object({
    type       = string
    expression = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.placement_constraints : contains(["distinctInstance", "memberOf"], c.type)])
    error_message = "placement_constraints type must be one of: distinctInstance, memberOf"
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "initial_role" {
  description = "Name of the IAM role to use for both task role and execution role"
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Only needed when using cloudflare features"
  type        = string
  default     = ""
  sensitive   = true
}
