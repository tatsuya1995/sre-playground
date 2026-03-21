project = "sre-playground"
env     = "prod"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
availability_zones   = ["ap-northeast-1a", "ap-northeast-1c"]

db_name               = "sre_playground"
db_username           = "laravel"
db_password_secret_id = "sre-playground/prod/db_password"

app_key    = "base64:yHUVxqbhVVjVcEbrZR76kDQXfuYOwf1CtNtbET1olvY="
sqs_queue   = "articles"
github_repo = "tatsuya1995/sre-playground"
