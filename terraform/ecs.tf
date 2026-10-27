resource "aws_secretsmanager_secret" "mirrord_api_key" {
  count                   = local.operator_hosted ? 0 : 1
  name_prefix             = "${var.name}/mirrord-api-key-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mirrord_api_key" {
  count         = local.operator_hosted ? 0 : 1
  secret_id     = aws_secretsmanager_secret.mirrord_api_key[0].id
  secret_string = var.mirrord_api_key
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "this" {
  name = var.name
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECS uses the execution role to pull images and to inject the secrets when a task starts.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = concat(aws_secretsmanager_secret.mirrord_api_key[*].arn, [aws_secretsmanager_secret.db_password.arn])
    }]
  })
}

locals {
  # MetalBear Cloud mode needs the API key, and the Cloud URLs only when they are not the defaults. Operator-hosted mode needs the EKS
  # endpoint, its CA, and the cluster name that the task signs its token for.
  mirrord_connection_env = local.operator_hosted ? [
    { name = "MIRRORD_OPERATOR_API_URL", value = data.aws_eks_cluster.operator[0].endpoint },
    { name = "MIRRORD_OPERATOR_EKS_CLUSTER_NAME", value = var.eks_cluster_name },
    { name = "MIRRORD_OPERATOR_API_CA_DATA", value = data.aws_eks_cluster.operator[0].certificate_authority[0].data },
    ] : [
    for env in [
      { name = "MIRRORD_METALBEAR_CLOUD_URL", value = var.mirrord_cloud_url },
      { name = "MIRRORD_SESSIONS_MANAGER_URL", value = var.mirrord_sessions_manager_url },
    ] : env if env.value != null
  ]

  mirrord_connection_secrets = local.operator_hosted ? [] : [
    { name = "MIRRORD_SESSIONS_MANAGER_API_KEY", valueFrom = aws_secretsmanager_secret.mirrord_api_key[0].arn },
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.this.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs"
    }
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = local.operator_hosted ? aws_iam_role.task[0].arn : null

  volume {
    name = "mirrord"
  }

  container_definitions = jsonencode([
    # Copies the bootstrap library into the shared volume before the app starts.
    {
      name             = "install-mirrord-remote-bootstrap"
      image            = var.mirrord_bootstrap_image
      essential        = false
      entryPoint       = ["/bin/sh", "-c"]
      command          = ["cp /opt/mirrord/lib/libmirrord_remote_bootstrap.so /mirrord/libmirrord_remote_bootstrap.so"]
      mountPoints      = [{ sourceVolume = "mirrord", containerPath = "/mirrord" }]
      logConfiguration = local.log_configuration
    },
    {
      name         = "app"
      image        = var.app_image
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      dependsOn    = [{ containerName = "install-mirrord-remote-bootstrap", condition = "SUCCESS" }]
      mountPoints  = [{ sourceVolume = "mirrord", containerPath = "/opt/mirrord/lib", readOnly = true }]
      environment = concat([
        { name = "LD_PRELOAD", value = "/opt/mirrord/lib/libmirrord_remote_bootstrap.so" },
        { name = "MIRRORD_REMOTE_SERVICE", value = var.mirrord_service },
        { name = "MIRRORD_REMOTE_ENVIRONMENT", value = var.mirrord_environment },
        { name = "DB_HOST", value = aws_db_instance.this.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.this.port) },
        { name = "DB_NAME", value = aws_db_instance.this.db_name },
        { name = "DB_USER", value = aws_db_instance.this.username },
      ], local.mirrord_connection_env)
      secrets = concat([
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
      ], local.mirrord_connection_secrets)
      logConfiguration = local.log_configuration
    },
  ])
}

# One task: a mirrord session is served by one replica of the service.
resource "aws_ecs_service" "app" {
  name            = var.mirrord_service
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.task.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http, aws_secretsmanager_secret_version.mirrord_api_key, aws_eks_access_entry.task]

  lifecycle {
    precondition {
      condition     = (var.mirrord_api_key != null) != (var.eks_cluster_name != null)
      error_message = "Set exactly one of mirrord_api_key (MetalBear Cloud mode) or eks_cluster_name (operator-hosted mode)."
    }
  }
}
