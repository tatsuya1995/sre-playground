# Terraform 基礎メモ

実際に手を動かしながら疑問に思った点をまとめたドキュメント。

---

## ディレクトリ構造の役割

```
terraform/
├── modules/          # リソースの定義（何を作るかの設計図）
│   └── network/
│       ├── main.tf       # 実際のリソース定義
│       ├── variables.tf  # 受け取る変数の型・説明
│       └── outputs.tf    # 他モジュールに渡す値
└── envs/
    └── prod/         # 環境ごとの値と実行エントリーポイント
        ├── main.tf       # provider設定・moduleの呼び出し
        ├── variables.tf  # 変数の型定義
        └── terraform.tfvars  # 変数の実際の値
```

---

## modules と envs の関係

**modulesは「型と定義だけ」持つ。値は持たない。**

```hcl
# modules/network/variables.tf → 型と説明だけ
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}
```

```hcl
# envs/prod/terraform.tfvars → 実際の値
vpc_cidr = "10.0.0.0/16"
```

```hcl
# envs/prod/main.tf → moduleに値を渡す
module "network" {
  source   = "../../modules/network"
  vpc_cidr = var.vpc_cidr   # tfvarsの値をmoduleに渡している
}
```

**同じmoduleをstaging/prodで使い回せるのがこの設計のメリット。**

```
envs/staging/terraform.tfvars → vpc_cidr = "10.1.0.0/16"
envs/prod/terraform.tfvars    → vpc_cidr = "10.0.0.0/16"
```

---

## エントリーポイント

`terraform` コマンドは**カレントディレクトリの`*.tf`を全部読む**仕様。

```bash
cd terraform/envs/prod
terraform init
terraform plan
terraform apply
```

`envs/prod/`に`cd`した状態で実行するのがお作法。

---

## terraform plan が読むファイル

```
terraform.tfvars         # 値
  └─ variables.tf        # 型チェック
      └─ main.tf         # moduleの呼び出し
          └─ modules/network/main.tf  # ここに書いたリソースが差分として表示される
```

stateが空（初回）の場合、tfファイルに書いた全リソースが `+ create` として表示される。

---

## outputs.tf

**2つの使われ方がある。**

### ① terraform apply後にターミナルに表示される

```bash
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

vpc_id            = "vpc-0abc1234"
public_subnet_ids = ["subnet-0aaa", "subnet-0bbb"]
```

### ② 他のモジュールからリソースIDを参照するために使う

```hcl
# envs/prod/main.tf
module "alb" {
  source            = "../../modules/alb"
  vpc_id            = module.network.vpc_id           # networkのoutputを参照
  public_subnet_ids = module.network.public_subnet_ids
}
```

モジュール間でリソースIDを受け渡す仕組みがoutputs。

---

## .terraform.lock.hcl

**Node.jsの`package-lock.json`と同じ役割。**

| | Node.js | Terraform |
|---|---|---|
| バージョン制約 | `package.json` | `main.tf` の `required_providers` |
| 実際のバージョン固定 | `package-lock.json` | `.terraform.lock.hcl` |

`terraform init` 時に自動生成される。チームで同じプロバイダーバージョンを使うために**Gitにコミットする**。

---

## tfstate（terraform.tfstate）

**TerraformがAWSの実際の状態を記録するファイル。**

- `terraform apply` 実行時にカレントディレクトリに自動生成される
- `terraform plan` はこのstateと現在のtfファイルを比較して差分を出す

### ローカルstateの問題点

| 問題 | 内容 |
|---|---|
| チーム共有できない | 自分のPCにしかない |
| 同時applyで壊れる | ロックがない |
| 削除するとリソースを把握できなくなる | 復元不可 |

→ 本番はS3 backendに置く。

---

## backend

**stateをどこに保存するかの設定。**

```
backend = "stateをどこに置くか"の設定

local  → 手元のPC（デフォルト・何も書かない場合）
s3     → AWSのS3バケット（チーム開発・本番向け）
```

```hcl
# S3 backendの設定例（envs/prod/main.tf）
terraform {
  backend "s3" {
    bucket         = "sre-playground-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-lock"  # 同時apply防止のロック
  }
}
```

S3バケットとDynamoDBテーブルはTerraform管理外で手動で先に作る必要がある。

---

## terraform init が必要なタイミング

`terraform init` は毎回実行する必要はない。以下のタイミングでのみ必要。

| タイミング | 理由 |
|---|---|
| 初回セットアップ時 | プロバイダー（AWS等）をダウンロードする |
| 新しいモジュールを追加したとき | モジュールの参照を `.terraform/` に登録する |
| `backend` の設定を変えたとき | stateの保存先が変わるため再初期化が必要 |
| プロバイダーのバージョンを変えたとき | 新しいバージョンをダウンロードする |
| 別のマシンやCIで初めて実行するとき | `.terraform/` はgitignoreされているため |

```bash
# 新しいモジュールを追加した後は init が必要
module "sg" {
  source = "../../modules/sg"  # ← これを追加したら terraform init
  ...
}
```

`plan` や `apply` だけの場合は `init` 不要。

---

## -auto-approve について

`terraform apply` や `terraform destroy` は通常 `yes/no` の確認を求めるが、`-auto-approve` をつけると確認をスキップして自動実行する。

```bash
terraform apply -auto-approve   # 確認なしで即apply
terraform destroy -auto-approve # 確認なしで即destroy
```

**使い所**
- CI/CDパイプラインでの自動デプロイ
- スクリプト内での実行

**注意点**
- 本番環境では使わない。確認なしで意図しないリソースが削除・変更されるリスクがある
- 手動実行時は通常通り `yes/no` で確認する習慣をつける

---

## .gitignore で除外すべきもの

```gitignore
# stateファイル（AWSリソースの情報が全部入っている）
*.tfstate
*.tfstate.backup

# terraform initで生成されるディレクトリ（重い・環境依存）
.terraform/

# クラッシュログ
crash.log
```

- `.terraform.lock.hcl` はコミットする
- `terraform.tfvars` に機密値（DBパスワードなど）を書いた場合はgitignoreに追加する

---

## モジュール間の値の受け渡し

あるモジュールのoutputを別モジュールのinputに渡すパターン。

```hcl
# SQSモジュールが作ったキュー名をECSモジュールに渡す例
module "sqs" {
  source     = "../../modules/sqs"
  queue_name = var.sqs_queue  # "articles"
}

locals {
  # queue_url: https://sqs.ap-northeast-1.amazonaws.com/123456789/sre-playground-prod-articles
  # queue_name: sre-playground-prod-articles
  # prefixはqueue_urlからqueue_nameを除いた部分
  sqs_prefix = trimsuffix(module.sqs.queue_url, "/${module.sqs.queue_name}")
}

module "ecs" {
  sqs_prefix = local.sqs_prefix
  sqs_queue  = module.sqs.queue_name  # "sre-playground-prod-articles"
}
```

**ポイント**: `var.sqs_queue`（"articles"）ではなく `module.sqs.queue_name`（"sre-playground-prod-articles"）を使う。
TerraformのSQSリソースはキュー名を `{project}-{env}-{name}` で作成するため、実際の名前と `var.sqs_queue` はズレる。

---

## ECSデプロイ後の確認手順

### 1. タスクが新しいイメージを使っているか確認
```bash
TASK_ARN=$(aws ecs list-tasks --cluster <cluster> --service-name <service> \
  --region ap-northeast-1 --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster <cluster> --tasks $TASK_ARN \
  --region ap-northeast-1 \
  --query 'tasks[0].containers[0].imageDigest' --output text
```

### 2. タスク定義の環境変数を確認
```bash
aws ecs describe-task-definition \
  --task-definition <family>:<revision> \
  --region ap-northeast-1 \
  --query 'taskDefinition.containerDefinitions[?name==`app`].environment'
```

### 3. ECSサービスのイベント確認
```bash
aws ecs describe-services \
  --cluster <cluster> --services <service> \
  --region ap-northeast-1 \
  --query 'services[0].events[:5]'
```

---

## Laravel 11以降の環境変数の変更点

Laravel 11 から一部の設定キーが変わっており、旧来の変数名を設定しても無視される。

| 設定 | Laravel 10以前 | Laravel 11以降 |
|---|---|---|
| キャッシュドライバー | `CACHE_DRIVER` | `CACHE_STORE` |
| DB接続 | デフォルト `sqlite` のまま | 同様（要 `DB_CONNECTION=mysql` 明示） |

セッションドライバーは `SESSION_DRIVER` のまま変わらないが、デフォルト値が `file` から `database` に変更されている。ECS環境では `SESSION_DRIVER=redis` を明示しないとセッションがDBに保存しようとして `sessions` テーブル不在エラーが起きる。

```hcl
# ECSタスク定義に必須の環境変数（Laravel 11以降）
{ name = "DB_CONNECTION",   value = "mysql"  }
{ name = "CACHE_STORE",     value = "redis"  }  # CACHE_DRIVER は無効
{ name = "SESSION_DRIVER",  value = "redis"  }  # デフォルトがdatabaseになったため明示必要
```

---

## ECSコンテナのログをCloudWatchで見る

Laravelのデフォルトログはファイル（`storage/logs/laravel.log`）に書き出されるため、ECSでは見えない。
`LOG_CHANNEL=stderr` を設定するとstderrに出力され、CloudWatchで確認できる。

```hcl
# ECSタスク定義の環境変数に追加
{ name = "LOG_CHANNEL", value = "stderr" }
```

```bash
# CloudWatchでworkerのログを確認
aws logs tail /ecs/<project>-<env> \
  --region ap-northeast-1 \
  --log-stream-name-prefix worker/worker \
  --follow
```
