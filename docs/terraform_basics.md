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
