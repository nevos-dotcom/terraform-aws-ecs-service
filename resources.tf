resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${data.aws_ecs_cluster.ecs_cluster.cluster_name}/${var.ecs_service_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_anomaly_detector" "this" {
  count                   = var.log_anomaly_detection.enabled ? 1 : 0
  detector_name           = aws_cloudwatch_log_group.ecs_log_group.name
  log_group_arn_list      = [aws_cloudwatch_log_group.ecs_log_group.arn]
  evaluation_frequency    = var.log_anomaly_detection.evaluation_frequency
  anomaly_visibility_time = var.log_anomaly_detection.anomaly_visibility_time
  filter_pattern          = var.log_anomaly_detection.filter_pattern != "" ? var.log_anomaly_detection.filter_pattern : null
  enabled                 = true
  tags                    = local.common_tags
}

resource "aws_alb_target_group" "target_group" {
  count                = var.application_load_balancer.enabled ? 1 : 0
  name                 = local.main_target_group_name
  port                 = var.application_load_balancer.container_port
  protocol             = var.application_load_balancer.protocol
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.application_load_balancer.deregister_deregistration_delay

  dynamic "stickiness" {
    for_each = var.application_load_balancer.stickiness ? [1] : []
    content {
      cookie_duration = var.application_load_balancer.stickiness_ttl
      cookie_name     = var.application_load_balancer.cookie_name
      type            = var.application_load_balancer.stickiness_type
    }
  }

  health_check {
    healthy_threshold   = var.application_load_balancer.health_check_threshold_healthy
    interval            = var.application_load_balancer.health_check_interval_sec
    protocol            = var.application_load_balancer.health_check_protocol
    matcher             = var.application_load_balancer.health_check_protocol == "HTTP" ? var.application_load_balancer.health_check_matcher : null
    timeout             = var.application_load_balancer.health_check_timeout_sec
    path                = var.application_load_balancer.health_check_protocol == "HTTP" ? var.application_load_balancer.health_check_path : null
    unhealthy_threshold = var.application_load_balancer.health_check_threshold_unhealthy
    port                = var.application_load_balancer.health_check_port
  }

  depends_on = [aws_alb_target_group.target_group_additional]
  tags       = local.common_tags
}

resource "aws_alb_target_group" "target_group_additional" {
  for_each = {
    for idx, alb in var.additional_load_balancers : idx => alb
    if alb.enabled && try(alb.action_type, "forward") == "forward"
  }

  name                 = local.additional_target_group_names[each.key]
  port                 = each.value.container_port
  protocol             = each.value.protocol
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = each.value.deregister_deregistration_delay

  dynamic "stickiness" {
    for_each = each.value.stickiness ? [1] : []
    content {
      cookie_duration = each.value.stickiness_ttl
      cookie_name     = each.value.cookie_name
      type            = each.value.stickiness_type
    }
  }

  health_check {
    healthy_threshold   = each.value.health_check_threshold_healthy
    interval            = each.value.health_check_interval_sec
    protocol            = each.value.health_check_protocol
    matcher             = each.value.health_check_protocol == "HTTP" ? each.value.health_check_matcher : null
    timeout             = each.value.health_check_timeout_sec
    path                = each.value.health_check_protocol == "HTTP" ? each.value.health_check_path : null
    unhealthy_threshold = each.value.health_check_threshold_unhealthy
    port                = each.value.health_check_port
  }

  tags = local.common_tags
}

########################
# Listener rules for ALB
#########################

resource "aws_lb_listener_rule" "rule" {
  count = var.application_load_balancer.enabled && var.application_load_balancer.protocol == "HTTP" ? 1 : 0

  listener_arn = var.application_load_balancer.listener_arn

  dynamic "action" {
    for_each = var.application_load_balancer.action_type == "forward" ? [1] : []
    content {
      type = "forward"

      forward {
        target_group {
          arn = aws_alb_target_group.target_group[0].arn
        }

        stickiness {
          enabled  = lookup(var.application_load_balancer, "stickiness", false)
          duration = lookup(var.application_load_balancer, "stickiness_ttl", 300)
        }
      }
    }
  }

  dynamic "action" {
    for_each = var.application_load_balancer.action_type == "fixed-response" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Unauthorized"
        status_code  = "401"
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.application_load_balancer.host) > 0 ? [1] : []
    content {
      host_header {
        values = [var.application_load_balancer.host]
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.application_load_balancer.path) > 0 ? [1] : []
    content {
      path_pattern {
        values = [var.application_load_balancer.path]
      }
    }
  }

  depends_on = [aws_alb_target_group.target_group, aws_lb_listener_rule.rule_additional, aws_alb_target_group.target_group_additional]
  tags       = local.common_tags
}


resource "aws_lb_listener_rule" "rule_additional" {
  for_each = {
    for idx, alb in var.additional_load_balancers : idx => alb
    if alb.enabled && alb.protocol == "HTTP"
  }

  listener_arn = each.value.listener_arn

  dynamic "action" {
    for_each = each.value.action_type == "forward" ? [1] : []
    content {
      type = "forward"

      forward {
        target_group {
          arn = aws_alb_target_group.target_group_additional[each.key].arn
        }

        stickiness {
          enabled  = lookup(each.value, "stickiness", false)
          duration = lookup(each.value, "stickiness_ttl", 300)
        }
      }
    }
  }

  dynamic "action" {
    for_each = each.value.action_type == "fixed-response" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Unauthorized"
        status_code  = "401"
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.host) > 0 ? [1] : []
    content {
      host_header {
        values = [each.value.host]
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path) > 0 ? [1] : []
    content {
      path_pattern {
        values = [each.value.path]
      }
    }
  }

  depends_on = [aws_alb_target_group.target_group_additional]
  tags       = local.common_tags
}

########################
# Listeners for NLB
#########################

resource "aws_lb_listener" "tcp_listener" {
  count = var.application_load_balancer.enabled && var.application_load_balancer.protocol == "TCP" ? 1 : 0

  load_balancer_arn = var.application_load_balancer.nlb_arn
  port              = var.application_load_balancer.nlb_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.target_group[0].arn
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "tcp_listener_additional" {
  for_each = {
    for idx, alb in var.additional_load_balancers : idx => alb
    if alb.enabled && alb.protocol == "TCP"
  }

  load_balancer_arn = each.value.nlb_arn
  port              = each.value.nlb_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.target_group_additional[each.key].arn
  }

  depends_on = [aws_alb_target_group.target_group_additional]
  tags       = local.common_tags
}

########################
# Initial Task Definition
#########################

resource "aws_ecs_task_definition" "task_definition" {
  family                   = "${data.aws_ecs_cluster.ecs_cluster.cluster_name}_${var.ecs_service_name}"
  network_mode             = var.network_mode
  requires_compatibilities = [var.ecs_launch_type]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  task_role_arn            = var.initial_role != "" ? var.initial_role : null
  execution_role_arn       = var.initial_role != "" ? var.initial_role : null
  container_definitions    = local.container_definitions_json
  tags                     = local.common_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_ecs_service" "ecs_service" {
  name                               = var.ecs_service_name
  cluster                            = data.aws_ecs_cluster.ecs_cluster.id
  task_definition                    = aws_ecs_task_definition.task_definition.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment.min_healthy_percent
  deployment_maximum_percent         = var.deployment.max_healthy_percent

  enable_execute_command = var.enable_execute_command
  launch_type            = var.capacity_provider_strategy == "" ? "FARGATE" : null
  scheduling_strategy    = "REPLICA"
  propagate_tags         = "SERVICE"
  platform_version       = var.ecs_launch_type == "FARGATE" ? "LATEST" : ""
  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = var.deployment.circuit_breaker_enabled
    rollback = var.deployment.rollback_enabled
  }

  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? [1] : []
    content {
      security_groups  = var.security_group_ids
      subnets          = var.subnet_ids
      assign_public_ip = var.assign_public_ip
    }
  }

  dynamic "alarms" {
    for_each = var.deployment.cloudwatch_alarm_enabled ? [1] : []
    content {
      alarm_names = var.deployment.cloudwatch_alarm_names
      enable      = true
      rollback    = var.deployment.cloudwatch_alarm_rollback
    }
  }

  dynamic "load_balancer" {
    for_each = var.application_load_balancer.enabled && var.application_load_balancer.action_type == "forward" ? [1] : []
    content {
      target_group_arn = aws_alb_target_group.target_group[0].arn
      container_name   = var.container_name
      container_port   = var.application_load_balancer.container_port
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy != "" ? [1] : []
    content {
      capacity_provider = var.capacity_provider_strategy
      weight            = 1
      base              = 0
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  dynamic "placement_constraints" {
    for_each = var.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }

  dynamic "load_balancer" {
    for_each = {
      for idx, alb in var.additional_load_balancers : idx => alb
      if alb.enabled && alb.action_type == "forward"
    }
    content {
      target_group_arn = aws_alb_target_group.target_group_additional[load_balancer.key].arn
      container_name   = var.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_connect_configuration" {
    for_each = var.service_connect.enabled ? [1] : []
    content {
      enabled   = true
      namespace = var.ecs_cluster_name

      dynamic "service" {
        for_each = contains(["client-server"], var.service_connect.type) ? [1] : []
        content {
          port_name      = "default"
          discovery_name = var.service_connect.name
          client_alias {
            port     = var.service_connect.port
            dns_name = var.service_connect.name
          }
          timeout {
            idle_timeout_seconds        = var.service_connect.appProtocol == "http" ? 0 : null
            per_request_timeout_seconds = var.service_connect.appProtocol == "http" ? var.service_connect.timeout : null
          }
        }
      }

      dynamic "service" {
        for_each = var.service_connect.type == "client-server" && length(var.service_connect.additional_ports) > 0 ? var.service_connect.additional_ports : []
        content {
          port_name      = service.value.name
          discovery_name = "${var.service_connect.name}-${service.value.name}"
          client_alias {
            port     = service.value.port
            dns_name = var.service_connect.name
          }
          timeout {
            idle_timeout_seconds        = 0
            per_request_timeout_seconds = var.service_connect.timeout
          }
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [task_definition, platform_version, desired_count, service_connect_configuration.0.namespace]
  }

  depends_on = [
    aws_lb_listener_rule.rule,
    aws_lb_listener_rule.rule_additional,
    aws_alb_target_group.target_group,
    aws_alb_target_group.target_group_additional,
    aws_ecs_task_definition.task_definition
  ]
}

resource "aws_appautoscaling_target" "ecs_target" {
  count = (var.cpu_auto_scaling.enabled || var.memory_auto_scaling.enabled || var.sqs_autoscaling.enabled || var.schedule_auto_scaling.enabled) ? 1 : 0
  min_capacity = max(
    try(var.cpu_auto_scaling.min_replicas, 0),
    try(var.memory_auto_scaling.min_replicas, 0),
    try(var.sqs_autoscaling.min_replicas, 0),
    try(var.schedule_auto_scaling.min_replicas, 0)
  )
  max_capacity = max(
    try(var.cpu_auto_scaling.max_replicas, 0),
    try(var.memory_auto_scaling.max_replicas, 0),
    try(var.sqs_autoscaling.max_replicas, 0),
    try(var.schedule_auto_scaling.max_replicas, 0)
  )
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.ecs_service]
  lifecycle {
    ignore_changes = [min_capacity, max_capacity]
  }
}

resource "aws_appautoscaling_scheduled_action" "ecs_scheduled_scaling" {
  count = var.schedule_auto_scaling.enabled ? length(var.schedule_auto_scaling.schedules) : 0

  name               = "${var.ecs_cluster_name}-${var.ecs_service_name}-${var.schedule_auto_scaling.schedules[count.index].schedule_name}"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  schedule           = var.schedule_auto_scaling.schedules[count.index].schedule_expression
  timezone           = var.schedule_auto_scaling.schedules[count.index].time_zone
  start_time         = timeadd(timestamp(), "100s")
  scalable_target_action {
    min_capacity = try(var.schedule_auto_scaling.schedules[count.index].min_replicas, 0)
    max_capacity = try(var.schedule_auto_scaling.schedules[count.index].max_replicas, 0)
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_target.ecs_target]
  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "aws_appautoscaling_policy" "scale_by_cpu_policy" {
  count              = var.cpu_auto_scaling.enabled ? 1 : 0
  name               = "${var.ecs_cluster_name}/${var.ecs_service_name}/scale-by-cpu-policy"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    disable_scale_in   = false
    scale_in_cooldown  = var.cpu_auto_scaling.scale_in_cooldown
    scale_out_cooldown = var.cpu_auto_scaling.scale_out_cooldown
    target_value       = var.cpu_auto_scaling.target_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_target.ecs_target]
}

resource "aws_appautoscaling_policy" "scale_by_memory_policy" {
  count              = var.memory_auto_scaling.enabled ? 1 : 0
  name               = "${var.ecs_cluster_name}/${var.ecs_service_name}/scale-by-memory-policy"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    disable_scale_in   = false
    scale_in_cooldown  = var.memory_auto_scaling.scale_in_cooldown
    scale_out_cooldown = var.memory_auto_scaling.scale_out_cooldown
    target_value       = var.memory_auto_scaling.target_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_target.ecs_target]
}

###############################################################################
# SQS AUTO SCALING - SCALE OUT POLICY (Proportional Step Ladder)
###############################################################################
resource "aws_appautoscaling_policy" "sqs_scale_out" {
  count              = var.sqs_autoscaling.enabled ? 1 : 0
  name               = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-scale-out"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = local.sqs_scale_out_cooldown
    metric_aggregation_type = local.sqs_aggregation_type_out

    dynamic "step_adjustment" {
      for_each = local.sqs_scale_out_steps
      content {
        metric_interval_lower_bound = step_adjustment.value.lower
        metric_interval_upper_bound = step_adjustment.value.upper
        scaling_adjustment          = step_adjustment.value.change
      }
    }
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_target.ecs_target]
}

###############################################################################
# SQS AUTO SCALING - SCALE IN POLICY (Conservative single step)
###############################################################################
resource "aws_appautoscaling_policy" "sqs_scale_in" {
  count              = var.sqs_autoscaling.enabled ? 1 : 0
  name               = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-scale-in"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = local.sqs_scale_in_cooldown
    metric_aggregation_type = local.sqs_aggregation_type_in

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = local.sqs_scale_in_step
    }
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_target.ecs_target]
}

###############################################################################
# SQS AUTO SCALING - SCALE OUT ALARM (Age-based, fast detection)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "sqs_age_out" {
  count               = var.sqs_autoscaling.enabled && local.sqs_age_sma_points <= 1 ? 1 : 0
  alarm_name          = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-age-out"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = var.sqs_autoscaling.scale_out_age_seconds
  alarm_description   = "Scale OUT when SQS ApproximateAgeOfOldestMessage exceeds ${var.sqs_autoscaling.scale_out_age_seconds}s"
  datapoints_to_alarm = 3
  alarm_actions       = [aws_appautoscaling_policy.sqs_scale_out[0].arn]
  treat_missing_data  = local.sqs_treat_missing_out

  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  period      = 60
  statistic   = "Average"
  dimensions = {
    QueueName = local.sqs_out_queue
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_policy.sqs_scale_out]
  tags       = local.common_tags
}

###############################################################################
# SQS AUTO SCALING - SCALE OUT ALARM with SMA (Age-based, smoothed)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "sqs_age_out_sma" {
  count               = var.sqs_autoscaling.enabled && local.sqs_age_sma_points > 1 ? 1 : 0
  alarm_name          = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-age-out"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = var.sqs_autoscaling.scale_out_age_seconds
  alarm_description   = "Scale OUT when SQS ApproximateAgeOfOldestMessage (${local.sqs_age_sma_points}-point SMA) exceeds ${var.sqs_autoscaling.scale_out_age_seconds}s"
  datapoints_to_alarm = 3
  alarm_actions       = [aws_appautoscaling_policy.sqs_scale_out[0].arn]
  treat_missing_data  = local.sqs_treat_missing_out

  metric_query {
    id          = "age_sma"
    expression  = "(${join(" + ", [for i in range(local.sqs_age_sma_points) : "m${i}"])}) / ${local.sqs_age_sma_points}"
    label       = "Age SMA"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = range(local.sqs_age_sma_points)
    content {
      id = "m${metric_query.value}"
      metric {
        metric_name = "ApproximateAgeOfOldestMessage"
        namespace   = "AWS/SQS"
        period      = 60
        stat        = "Average"
        dimensions = {
          QueueName = local.sqs_out_queue
        }
      }
      return_data = false
    }
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_policy.sqs_scale_out]
  tags       = local.common_tags
}

###############################################################################
# SQS AUTO SCALING - SCALE IN READINESS ALARM (Age-based, conservative)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "sqs_age_in_ready" {
  count               = var.sqs_autoscaling.enabled ? 1 : 0
  alarm_name          = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-age-in-ready"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = var.sqs_autoscaling.scale_in_age_seconds
  alarm_description   = "Scale IN readiness: ApproximateAgeOfOldestMessage below ${var.sqs_autoscaling.scale_in_age_seconds}s"
  datapoints_to_alarm = 3
  treat_missing_data  = local.sqs_treat_missing_in

  # If require_empty_for_scale_in is false, trigger scale-in directly
  alarm_actions = local.sqs_require_empty_for_scale_in ? [] : [aws_appautoscaling_policy.sqs_scale_in[0].arn]

  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  period      = 300
  statistic   = "Average"
  dimensions = {
    QueueName = local.sqs_in_queue
  }

  depends_on = [aws_ecs_service.ecs_service, aws_appautoscaling_policy.sqs_scale_in]
  tags       = local.common_tags
}

###############################################################################
# SQS AUTO SCALING - QUEUE EMPTY CHECKS (for safe scale-in)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "sqs_visible_zero" {
  count               = var.sqs_autoscaling.enabled && local.sqs_require_empty_for_scale_in ? 1 : 0
  alarm_name          = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-visible-zero"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = local.sqs_empty_eval_periods
  threshold           = 0
  alarm_description   = "Queue has no visible messages"
  datapoints_to_alarm = local.sqs_empty_eval_periods
  treat_missing_data  = "ignore"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  period      = local.sqs_empty_period_seconds
  statistic   = "Maximum"
  dimensions = {
    QueueName = local.sqs_in_queue
  }

  depends_on = [aws_ecs_service.ecs_service]
  tags       = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_notvisible_zero" {
  count               = var.sqs_autoscaling.enabled && local.sqs_require_empty_for_scale_in ? 1 : 0
  alarm_name          = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-notvisible-zero"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = local.sqs_empty_eval_periods
  threshold           = 0
  alarm_description   = "Queue has no in-flight messages"
  datapoints_to_alarm = local.sqs_empty_eval_periods
  treat_missing_data  = "ignore"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesNotVisible"
  period      = local.sqs_empty_period_seconds
  statistic   = "Maximum"
  dimensions = {
    QueueName = local.sqs_in_queue
  }

  depends_on = [aws_ecs_service.ecs_service]
  tags       = local.common_tags
}

###############################################################################
# SQS AUTO SCALING - COMPOSITE SCALE-IN SAFETY ALARM
###############################################################################
resource "aws_cloudwatch_composite_alarm" "sqs_scale_in_safe" {
  count             = var.sqs_autoscaling.enabled && local.sqs_require_empty_for_scale_in ? 1 : 0
  alarm_name        = "${var.ecs_cluster_name}/${var.ecs_service_name}/sqs-scale-in-safe"
  alarm_description = "Safe to scale IN: age low AND queue empty (visible AND not-visible)"

  alarm_actions = [aws_appautoscaling_policy.sqs_scale_in[0].arn]

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.sqs_age_in_ready[0].alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.sqs_visible_zero[0].alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.sqs_notvisible_zero[0].alarm_name})"

  depends_on = [
    aws_ecs_service.ecs_service,
    aws_appautoscaling_policy.sqs_scale_in,
    aws_cloudwatch_metric_alarm.sqs_age_in_ready,
    aws_cloudwatch_metric_alarm.sqs_visible_zero,
    aws_cloudwatch_metric_alarm.sqs_notvisible_zero
  ]
  tags = local.common_tags
}


###############################################################################
# ECR REPOSITORY
###############################################################################
module "ecr" {
  count   = var.ecr.create_repo ? 1 : 0
  source  = "terraform-aws-modules/ecr/aws"
  version = "2.3.0"

  repository_name                 = var.ecr.repo_name != "" ? var.ecr.repo_name : var.ecs_service_name
  repository_image_tag_mutability = var.ecr.mutability
  attach_repository_policy        = false
  repository_lifecycle_policy = jsonencode({
    rules = concat(
      [
        {
          rulePriority = 1,
          description  = "Protect ${join(", ", var.ecr.protected_prefixes)} branches tags",
          selection = {
            tagStatus     = "tagged",
            tagPrefixList = var.ecr.protected_prefixes,
            countType     = "imageCountMoreThan",
            countNumber   = var.ecr.protected_retention
          },
          action = {
            type = "expire"
          }
        }
      ],
      [
        for idx, prefix in var.ecr.versioned_prefixes : {
          rulePriority = idx + 2, # Dynamic priority starting from 2
          description  = "Keep number of latest releases images for ${prefix}",
          selection = {
            tagStatus     = "tagged",
            tagPrefixList = [prefix],
            countType     = "imageCountMoreThan",
            countNumber   = var.ecr.versioned_retention
          },
          action = {
            type = "expire"
          }
        }
      ],
      [
        {
          rulePriority = length(var.ecr.versioned_prefixes) + 2,
          description  = "Expire all tagged images older than ${var.ecr.tagged_ttl_days} days",
          selection = {
            tagStatus      = "tagged",
            tagPatternList = ["*"],
            countType      = "sinceImagePushed",
            countUnit      = "days",
            countNumber    = var.ecr.tagged_ttl_days
          },
          action = {
            type = "expire"
          }
        },
        {
          rulePriority = length(var.ecr.versioned_prefixes) + 3,
          description  = "Remove untagged images older than ${var.ecr.untagged_ttl_days} days",
          selection = {
            tagStatus   = "untagged",
            countType   = "sinceImagePushed",
            countUnit   = "days",
            countNumber = var.ecr.untagged_ttl_days
          },
          action = {
            type = "expire"
          }
        }
      ]
    )
  })
  tags = local.common_tags
}

###############################################################################
# ROUTE 53 RECORDS
###############################################################################

# Route 53 record for main ALB
resource "aws_route53_record" "main_alb_record" {
  count   = var.application_load_balancer.enabled && var.application_load_balancer.route_53_host_zone_id != "" && var.application_load_balancer.host != "" ? 1 : 0
  zone_id = var.application_load_balancer.route_53_host_zone_id
  name    = var.application_load_balancer.host
  type    = "A"

  alias {
    name                   = data.aws_lb.main_alb[0].dns_name
    zone_id                = data.aws_lb.main_alb[0].zone_id
    evaluate_target_health = true
  }
}

# Route 53 records for additional ALBs
resource "aws_route53_record" "additional_alb_records" {
  for_each = {
    for idx, alb in var.additional_load_balancers : idx => alb
    if alb.enabled && alb.route_53_host_zone_id != "" && alb.host != ""
  }

  zone_id = each.value.route_53_host_zone_id
  name    = each.value.host
  type    = "A"

  alias {
    name                   = data.aws_lb.additional_albs[each.key].dns_name
    zone_id                = data.aws_lb.additional_albs[each.key].zone_id
    evaluate_target_health = true
  }
}

###############################################################################
# CLOUDFLARE DNS RECORDS
###############################################################################

# Cloudflare record for main ALB
resource "cloudflare_record" "main_alb_record" {
  count   = var.application_load_balancer.enabled && var.application_load_balancer.cloudflare_zone_id != "" && var.application_load_balancer.host != "" ? 1 : 0
  zone_id = var.application_load_balancer.cloudflare_zone_id
  name    = var.application_load_balancer.host
  value   = data.aws_lb.main_alb_cloudflare[0].dns_name
  type    = "CNAME"
  ttl     = var.application_load_balancer.cloudflare_proxied ? 1 : var.application_load_balancer.cloudflare_ttl
  proxied = var.application_load_balancer.cloudflare_proxied
}

# Cloudflare records for additional ALBs
resource "cloudflare_record" "additional_alb_records" {
  for_each = {
    for idx, alb in var.additional_load_balancers : idx => alb
    if alb.enabled && alb.cloudflare_zone_id != "" && alb.host != ""
  }

  zone_id = each.value.cloudflare_zone_id
  name    = each.value.host
  value   = data.aws_lb.additional_albs_cloudflare[each.key].dns_name
  type    = "CNAME"
  ttl     = each.value.cloudflare_proxied ? 1 : each.value.cloudflare_ttl
  proxied = each.value.cloudflare_proxied
}