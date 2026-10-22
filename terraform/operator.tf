# Operator-hosted mode. The task authenticates to the EKS API server as its task role,
# which an access entry maps into the group that may register serverless agents.
# The task reaches the API server's public endpoint through the NAT gateway.

locals {
  operator_hosted = var.eks_cluster_name != null
}

data "aws_eks_cluster" "operator" {
  count = local.operator_hosted ? 1 : 0
  name  = var.eks_cluster_name
}

resource "aws_iam_role" "task" {
  count              = local.operator_hosted ? 1 : 0
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_eks_access_entry" "task" {
  count             = local.operator_hosted ? 1 : 0
  cluster_name      = var.eks_cluster_name
  principal_arn     = aws_iam_role.task[0].arn
  type              = "STANDARD"
  user_name         = "mirrord-ecs-${var.mirrord_service}"
  kubernetes_groups = [var.eks_workload_group]
}
