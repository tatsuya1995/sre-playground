# Datadog インテグレーション設計

## 全体アーキテクチャ

```
ECS Tasks (app / worker / batch)
  └─ datadog-agent サイドカー
        ├─ APM Trace Agent  ← ddtrace (Laravel) からトレース受信
        └─ DogStatsD        ← カスタムメトリクス受信

CloudWatch Logs (/ecs/sre-playground-prod)
  └─ Subscription Filter → Kinesis Data Firehose → Datadog

RDS / ElastiCache / SQS / ALB
  └─ CloudWatch Metrics → Datadog AWS Integration (Crawler)
```

---

## 監視対象と収集方法

| リソース | 収集方法 | 主要メトリクス |
|---|---|---|
| ECS コンテナ | Agent サイドカー | CPU・メモリ・再起動数 |
| Laravel APM | ddtrace + Agent サイドカー | レイテンシ・エラー率・トレース |
| RDS MySQL | AWS Integration (CloudWatch) | 接続数・レイテンシ・CPU |
| ElastiCache Redis | AWS Integration (CloudWatch) | ヒット率・Evictions・接続数 |
| SQS | AWS Integration (CloudWatch) | 滞留メッセージ数・最古メッセージ経過時間 |
| ALB | AWS Integration (CloudWatch) | 5xx数・レイテンシ・HealthyHostCount |

### 各リソースの補足

**ECS Fargate**
Fargate はホストへのアクセスが不可のためサイドカー方式が唯一の選択肢。
Agent が ECS タスクメタデータエンドポイント（v4）を自動検出してコンテナ統計を収集する。

**RDS / ElastiCache**
Agent からの直接 DB 接続は不要。CloudWatch Crawler で十分なメトリクスが取れる。
DB 直接接続による Database Monitoring（DBM）はプライベートサブネットのネットワーク設計変更が必要なため Phase 2 の判断とする。

**SQS**
`ApproximateNumberOfMessagesVisible`（滞留数）と `ApproximateAgeOfOldestMessage`（最古メッセージ経過時間）が worker 詰まりの検知に直結する主要アラート指標。

---

## Datadog Agent サイドカー設計

### コンテナ設定方針

3つのタスク定義（app / worker / batch）それぞれに `datadog-agent` コンテナを追加する。

```hcl
{
  name      = "datadog-agent"
  image     = "public.ecr.aws/datadog/agent:7"
  essential = false  # Agent がクラッシュしてもアプリに影響させない

  environment = [
    { name = "DD_SITE",                        value = "datadoghq.com" },
    { name = "ECS_FARGATE",                    value = "true" },
    { name = "DD_APM_ENABLED",                 value = "true" },
    { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
    { name = "DD_LOGS_ENABLED",                value = "false" },  # ログはLambda Forwarder経由
    { name = "DD_PROCESS_AGENT_ENABLED",       value = "false" },  # Fargateでは不要
    { name = "DD_ENV",                         value = "production" },
    { name = "DD_SERVICE",                     value = "sre-playground" },
  ]

  secrets = [
    { name = "DD_API_KEY", valueFrom = var.datadog_api_key_secret_arn }
  ]

  portMappings = [
    { containerPort = 8126, protocol = "tcp" },   # APM
    { containerPort = 8125, protocol = "udp" },   # DogStatsD
  ]

  # CPU 64 / Memory 256 程度
}
```

### タスクリソース

CloudWatch の実測値（2026-03-22 時点）から、現在の Memory 512MB で十分に余裕がある。

| タスク | 現在のメモリ使用量 | Agent 追加後の見込み | 判定 |
|---|---|---|---|
| app | ~20MB (3.9%) | ~276MB | **引き上げ不要** |
| worker | ~52MB (10.2%) | ~308MB | **引き上げ不要** |

タスクレベルの `cpu` / `memory` は変更しない。

### タスクロールへの権限追加

`ecs_task` ロールに ECS メタデータ取得権限を追加:
```
ecs:ListClusters
ecs:ListContainerInstances
ecs:DescribeContainerInstances
```

---

## ログ転送設計（CloudWatch → Datadog）

### 方式: Amazon Data Firehose（Datadog 推奨）

CloudWatch Logs に集約されたログを Kinesis Data Firehose 経由で Datadog に転送する。
Lambda Forwarder は旧来の方式で、Datadog 公式も Firehose への移行を推奨している。

```
CloudWatch Logs (/ecs/sre-playground-prod)
  └─ Subscription Filter
      └─ Kinesis Data Firehose
          └─ Datadog Logs HTTP Endpoint
```

### Lambda Forwarder との比較

| | Lambda Forwarder | Firehose |
|---|---|---|
| コスト | Lambda実行時間課金 | $0.029/GB（ログ量課金）|
| 管理コスト | Lambda関数の管理が必要 | マネージドサービス |
| Datadogの推奨 | 旧来の方式 | **現在の推奨** |
| このプロジェクトでの月額目安 | 〜数百円 | 〜数十円 |

Fluent Bit（FireLens）はサイドカーコンテナとして常時 Fargate リソースを消費するため（~$7〜10/月/タスク）、Datadog Agent サイドカーがすでにある本構成ではコスト面で不利。

### 構成要素

1. **Kinesis Data Firehose**: Datadog の HTTP エンドポイントを Destination として設定。`aws_kinesis_firehose_delivery_stream` で管理
2. **サブスクリプションフィルター**: `/ecs/sre-playground-prod` ロググループ → Firehose ARN。`aws_cloudwatch_log_subscription_filter` で管理
3. **Firehose → Datadog 認証**: Datadog API Key を Secrets Manager から参照
4. **IAM ロール**: CloudWatch Logs が Firehose にデータを書き込む権限

### ログのタグ付け

Firehose の処理設定でメタデータを付与。ストリームプレフィックス（nginx / app / worker / batch）はサービスタグとして識別される。

---

## Laravel APM（ddtrace）設計

### アプリケーション側の変更（Terraform外）

Dockerfileに ddtrace PHP 拡張のインストールを追加する。

```dockerfile
# datadog/dd-trace-php をインストール
RUN curl -LO https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php \
  && php datadog-setup.php --php-bin=all \
  && rm datadog-setup.php
```

### ECS 環境変数の追加（Terraform側）

app / worker / batch コンテナの `environment` に追加:

```hcl
{ name = "DD_AGENT_HOST",                    value = "localhost" }  # サイドカーと同一ネットワーク
{ name = "DD_TRACE_AGENT_PORT",              value = "8126" }
{ name = "DD_ENV",                           value = "production" }
{ name = "DD_SERVICE",                       value = "sre-playground-app" }
{ name = "DD_LOGS_INJECTION",                value = "true" }  # ログとトレースの相関付け
{ name = "DD_TRACE_LARAVEL_ENABLED",         value = "true" }
# workerタスクのみ
{ name = "DD_TRACE_QUEUE_PROPAGATION_ENABLED", value = "true" }  # SQS経由のトレース連結
# batchタスクのみ
{ name = "DD_TRACE_CLI_ENABLED",             value = "true" }
```

---

## Secrets Manager 設計

| Secret 名 | 内容 | 用途 |
|---|---|---|
| `sre-playground/prod/datadog_api_key` | Datadog API Key | ECS Agent・Lambda Forwarder |
| `sre-playground/prod/datadog_app_key` | Datadog App Key | Terraform Datadog Provider（Monitor作成用） |

- App Key は ECS コンテナには渡さない。Terraform 実行時のみ使用（GitHub Actions Secrets or ローカル環境変数）
- ECS タスク実行ロールの Secrets Manager 取得ポリシーに `datadog_api_key_secret_arn` を追加する

---

## Terraform 変更箇所

### 1. `modules/datadog/main.tf`（現在空）

実装するリソース:
- `aws_kinesis_firehose_delivery_stream`: Datadog HTTP エンドポイントを Destination とする Firehose ストリーム
- `aws_cloudwatch_log_subscription_filter`: ECS ロググループ → Firehose
- `aws_iam_role` / `aws_iam_role_policy`: CloudWatch Logs が Firehose に書き込む IAM ロール
- `datadog_integration_aws`: Datadog AWS Integration の有効化
- `datadog_monitor`: 主要アラート定義（後述）

### 2. `modules/datadog/variables.tf`（現在空）

追加する変数:
- `datadog_api_key_secret_arn`
- `log_group_name`
- `aws_account_id`
- `env`, `project`

### 3. `modules/ecs/main.tf` ✅ 実装済み

- 3タスク定義の `container_definitions` に `datadog-agent` サイドカー追加
- app / worker / batch コンテナの `environment` に ddtrace 設定追加
- `ecs_task_execution_secrets` ポリシーの Resource を配列化し `datadog_api_key_secret_arn` を追加
- タスクレベルの `cpu` / `memory` は実測値から変更不要と判断し据え置き

### 4. `modules/ecs/variables.tf` ✅ 実装済み

追加した変数:
- `datadog_api_key_secret_arn`

### 5. `envs/prod/main.tf` ✅ 実装済み

- `data "aws_secretsmanager_secret" "datadog_api_key"` を追加
- `module "ecs"` の呼び出しに `datadog_api_key_secret_arn` を追加

### 6. `envs/prod/variables.tf` ✅ 実装済み

追加した変数:
- `datadog_api_key_secret_id`

---

## モニター設計（アラート定義）

| 監視項目 | 条件 | 緊急度 |
|---|---|---|
| SQS 滞留メッセージ数 | `ApproximateNumberOfMessagesVisible` > 100 が5分継続 | Warning |
| SQS 最古メッセージ経過時間 | `ApproximateAgeOfOldestMessage` > 300秒 | Critical（worker停止の可能性）|
| ALB 5xx エラー率 | 5xx / 全リクエスト > 1% が5分継続 | Critical |
| ECS タスク数 | HealthyHostCount < 1 | Critical |
| RDS CPU | CPUUtilization > 80% が10分継続 | Warning |
| Redis Evictions | Evictions > 0 | Warning（メモリ不足のサイン）|

---

## 実装順序

1. ✅ Secrets Manager に API Key を登録（`sre-playground/prod/datadog_api_key`）
2. ✅ Terraform 修正 → apply（ECS タスク定義に Agent サイドカー追加）
3. Dockerfile に ddtrace を追加 → イメージビルド → デプロイ → APM 動作確認
4. `modules/datadog` に Firehose + サブスクリプションフィルターを実装 → apply（ログ転送）
5. Datadog Terraform Provider で Monitor / Dashboard を定義 → apply

---

## 実装済み設定（Phase 1: APM）

### 変更ファイル一覧

| ファイル | 変更内容 |
|---|---|
| `modules/ecs/variables.tf` | `datadog_api_key_secret_arn` 変数を追加 |
| `modules/ecs/main.tf` | IAM ポリシー更新・Agent サイドカー追加・ddtrace 環境変数追加 |
| `envs/prod/variables.tf` | `datadog_api_key_secret_id` 変数を追加 |
| `envs/prod/main.tf` | Secrets Manager の data source 追加・`module "ecs"` に ARN を渡す |
| `envs/prod/terraform.tfvars` | `datadog_api_key_secret_id` の値を設定 |

### IAM ポリシー変更

`ecs_task_execution_secrets` ポリシーの Resource を配列化し、Datadog API Key Secret への取得権限を追加。

```hcl
Resource = [var.db_password_secret_arn, var.datadog_api_key_secret_arn]
```

### Datadog Agent サイドカー（3タスク共通）

```hcl
{
  name      = "datadog-agent"
  image     = "public.ecr.aws/datadog/agent:7"
  essential = false  # Agent クラッシュ時もアプリに影響させない

  environment = [
    { name = "DD_SITE",                        value = "datadoghq.com" },
    { name = "ECS_FARGATE",                    value = "true" },   # Fargate用メタデータ収集を有効化
    { name = "DD_APM_ENABLED",                 value = "true" },   # トレース受信を有効化
    { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },   # DogStatsD受信
    { name = "DD_LOGS_ENABLED",                value = "false" },  # ログはFirehose経由のため無効
    { name = "DD_PROCESS_AGENT_ENABLED",       value = "false" },  # Fargateでは不要
    { name = "DD_ENV",                         value = var.env },
    # DD_SERVICE はタスクごとに異なる（下記参照）
  ]
  secrets = [
    { name = "DD_API_KEY", valueFrom = var.datadog_api_key_secret_arn },
  ]
  portMappings = [
    { containerPort = 8126, protocol = "tcp" },  # APM トレース受信
    { containerPort = 8125, protocol = "udp" },  # DogStatsD
  ]
}
```

### タスクごとの DD_SERVICE 設定

| タスク | DD_SERVICE |
|---|---|
| app | `sre-playground-app` |
| worker | `sre-playground-worker` |
| batch | `sre-playground-batch` |

Datadog APM 上でサービスごとにトレースが分離して表示される。

### アプリコンテナへの ddtrace 環境変数

**app / worker / batch 共通:**

| 環境変数 | 値 | 説明 |
|---|---|---|
| `DD_AGENT_HOST` | `localhost` | サイドカーと同一ネットワーク（awsvpc）のため localhost で到達できる |
| `DD_TRACE_AGENT_PORT` | `8126` | Agent の APM ポート |
| `DD_LOGS_INJECTION` | `true` | ログにトレースID・スパンIDを付与してログとトレースを相関付ける |
| `DD_TRACE_LARAVEL_ENABLED` | `true` | Laravel の自動インストルメンテーションを有効化 |

**worker のみ追加:**

| 環境変数 | 値 | 説明 |
|---|---|---|
| `DD_TRACE_QUEUE_PROPAGATION_ENABLED` | `true` | SQS経由のジョブに元のHTTPリクエストのトレースを連結する |

**batch のみ追加:**

| 環境変数 | 値 | 説明 |
|---|---|---|
| `DD_TRACE_CLI_ENABLED` | `true` | CLI（artisan コマンド）実行時のトレースを有効化 |

### Dockerfile への ddtrace 追加 

Terraform の環境変数（`DD_TRACE_LARAVEL_ENABLED` 等）は ddtrace PHP 拡張が存在する前提で動く。
拡張がインストールされていなければ環境変数は無視され、トレースは送信されない。

```
ECSタスク
├─ datadog-agent サイドカー（環境変数だけで動く）
└─ app コンテナ
     ├─ DD_AGENT_HOST=localhost など → 設定済み
     └─ ddtrace PHP拡張 → Dockerfile でインストールが必要
```

`app/Dockerfile` に以下を追加してイメージをビルドし直すことで APM が有効になる。

```dockerfile
RUN curl -LO https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php \
  && php datadog-setup.php --php-bin=all \
  && rm datadog-setup.php
```

---

## コスト影響

- **Fargate**: サイドカー分の CPU/Memory 増加（app・worker タスクが約2倍のリソースになる）
- **Firehose**: $0.029/GB のログデータ量課金。このプロジェクト規模では月数十円程度
- **Datadog**: Custom Metrics の数に応じて課金。DogStatsD でカスタムメトリクスを送る場合はメトリクス数を管理する
