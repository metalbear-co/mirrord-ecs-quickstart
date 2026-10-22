output "url" {
  description = "Public URL of the orders service."
  value       = "http://${aws_lb.this.dns_name}"
}

output "mirrord_target" {
  description = "The target.path and target.namespace for mirrord.json."
  value = {
    path      = "serverless/${var.mirrord_service}"
    namespace = var.mirrord_environment
  }
}

output "db_host" {
  description = "Private RDS endpoint. It does not resolve or connect from outside the VPC."
  value       = aws_db_instance.this.address
}

output "logs" {
  description = "Command that tails the service logs."
  value       = "aws logs tail ${aws_cloudwatch_log_group.this.name} --follow --region ${var.region}"
}
