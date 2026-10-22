# The database has no public endpoint. Only the ECS tasks can reach it.
resource "random_password" "db" {
  length           = 24
  override_special = "-_"
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "this" {
  identifier             = var.name
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  db_name                = "orders"
  username               = "orders"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name_prefix             = "${var.name}/db-password-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}
