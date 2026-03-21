# Secrets ManagerからDBパスワードを取得
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.db_password_secret_id
}

# サブネットグループ: RDSをプライベートサブネットに配置する
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.env}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids
}

# RDS MySQL インスタンス
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-${var.env}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.instance_class
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = data.aws_secretsmanager_secret_version.db_password.secret_string

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]

  # マルチAZはコスト削減のため無効
  multi_az = false

  # 削除時にスナップショットをスキップ
  skip_final_snapshot = true

  # 削除保護
  deletion_protection = false
}
