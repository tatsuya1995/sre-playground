terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 最初はローカルstate。動作確認後にS3 backendへ移行する
  # backend "s3" {
  #   bucket = "YOUR_BUCKET_NAME"
  #   key    = "prod/terraform.tfstate"
  #   region = "ap-northeast-1"
  # }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "network" {
  source = "../../modules/network"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "ecr" {
  source = "../../modules/ecr"

  project = var.project
  env     = var.env
}

module "sg" {
  source = "../../modules/sg"

  project = var.project
  env     = var.env
  vpc_id  = module.network.vpc_id
}

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  env               = var.env
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.sg.alb_sg_id
}

module "redis" {
  source = "../../modules/redis"

  project            = var.project
  env                = var.env
  private_subnet_ids = module.network.private_subnet_ids
  redis_sg_id        = module.sg.redis_sg_id
}

module "rds" {
  source = "../../modules/rds"

  project               = var.project
  env                   = var.env
  private_subnet_ids    = module.network.private_subnet_ids
  rds_sg_id             = module.sg.rds_sg_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password_secret_id = var.db_password_secret_id
}

# Secrets ManagerからARNを取得（ECSタスク定義で secrets 参照に使う）
data "aws_secretsmanager_secret" "db_password" {
  name = var.db_password_secret_id
}

module "sqs" {
  source = "../../modules/sqs"

  project    = var.project
  env        = var.env
  queue_name = var.sqs_queue
}

locals {
  # SQSキューURLからキュー名を除いたプレフィックスを導出
  # 例: https://sqs.ap-northeast-1.amazonaws.com/123456789012
  sqs_prefix = trimsuffix(module.sqs.queue_url, "/${module.sqs.queue_name}")
}

module "ecs" {
  source = "../../modules/ecs"

  project                = var.project
  env                    = var.env
  private_subnet_ids     = module.network.private_subnet_ids
  app_sg_id              = module.sg.app_sg_id
  target_group_arn       = module.alb.target_group_arn
  app_image              = "${module.ecr.app_repository_url}:latest"
  nginx_image            = "${module.ecr.nginx_repository_url}:latest"
  app_key                = var.app_key
  db_host                = module.rds.endpoint
  db_name                = var.db_name
  db_username            = var.db_username
  db_password_secret_arn = data.aws_secretsmanager_secret.db_password.arn
  redis_host             = module.redis.endpoint
  sqs_prefix             = local.sqs_prefix
  sqs_queue              = module.sqs.queue_name
}

module "eventbridge" {
  source = "../../modules/eventbridge"

  project             = var.project
  env                 = var.env
  ecs_cluster_arn     = module.ecs.cluster_arn
  task_definition_arn = module.ecs.batch_task_definition_arn
  private_subnet_ids  = module.network.private_subnet_ids
  app_sg_id           = module.sg.app_sg_id
}
