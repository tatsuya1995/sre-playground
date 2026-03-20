# SRE Playground - Article Collection App

RSSフィードから記事を収集するアプリケーション。

## アーキテクチャ

```
                        Docker Network
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  [Client]                                               │
  │     │ :8080                                             │
  │     ▼                                                   │
  │  ┌─────────────────┐                                    │
  │  │  nginx          │  :80 (内部)                        │
  │  └─────────────────┘──────────────────┐                 │
  │                                       ▼                 │
  │  ┌─────────────────┐  MySQL    ┌─────────────────┐      │
  │  │  mysql          │◀──────────│  app            │      │
  │  │  :3306          │  Redis    │                 │      │
  │  └─────────────────┘  ┌────────│                 │      │
  │                        │        └────────┬────────┘      │
  │  ┌─────────────────┐  │                │ SQS送信        │
  │  │  redis          │◀─┘        ┌────────▼────────┐      │
  │  │  :6379          │           │  localstack     │      │
  │  └─────────────────┘           │  :4566          │      │
  │                                └────────┬────────┘      │
  │                                         │ SQSポーリング  │
  │  ┌─────────────────┐           ┌────────▼────────┐      │
  │  │  mysql          │◀──────────│  worker         │      │
  │  │  (articlesへ保存)│  MySQL    │  queue:work sqs │      │
  │  └─────────────────┘           └─────────────────┘      │
  └─────────────────────────────────────────────────────────┘
```

### コンテナの依存関係

```
nginx ──depends_on──▶ app
app   ──depends_on──▶ mysql (healthy)
                   ──▶ redis
                   ──▶ localstack
worker──depends_on──▶ app
```

## サービス構成

| サービス | イメージ | 役割 |
|---|---|---|
| app | PHP-FPM | Laravel API サーバー |
| worker | PHP-FPM | SQS キューワーカー |
| nginx | nginx | リバースプロキシ (:8080) |
| mysql | mysql | データベース |
| redis | redis | セッション・キャッシュ |
| localstack | localstack | AWS SQS エミュレーター |

## API エンドポイント

### フィード

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/feeds` | フィード一覧取得 |
| POST | `/api/feeds` | フィード登録 & 記事取得ジョブ発行 |

**POST /api/feeds リクエスト例**
```bash
curl -X POST http://localhost:8080/api/feeds \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"name": "Qiita", "url": "https://qiita.com/popular-items/feed"}'
```

**レスポンス例 (201)**
```json
{
  "id": 1,
  "name": "Qiita",
  "url": "https://qiita.com/popular-items/feed",
  "last_fetched_at": null,
  "created_at": "2026-03-20T06:00:00.000000Z",
  "updated_at": "2026-03-20T06:00:00.000000Z"
}
```

### 記事

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/articles` | 記事一覧取得 (20件ページネーション) |
| GET | `/api/articles/{id}` | 記事詳細取得 |

## データの流れ

```
1. POST /api/feeds
   └─ FeedController::store()
        ├─ feeds テーブルに登録
        └─ FetchFeedJob を SQS に送信

2. worker コンテナ（常駐）
   └─ php artisan queue:work sqs
        └─ SQS をポーリング（3秒おき）
             └─ FetchFeedJob::handle()
                  ├─ フィード URL に HTTP GET
                  ├─ RSS/Atom XML をパース
                  ├─ 記事を articles テーブルに保存 (firstOrCreate)
                  └─ feeds.last_fetched_at を更新

3. php artisan feeds:fetch（バッチ実行）
   └─ FetchFeedsCommand::handle()
        └─ 全フィードをループして FetchFeedJob を SQS に送信
             └─ 以降は 2. と同じ流れ
```

本番では EventBridge（cron）が `php artisan feeds:fetch` をトリガーし、ECS タスクとして起動する。

## DB スキーマ

### feeds

| カラム | 型 | 説明 |
|---|---|---|
| id | bigint | PK |
| name | string | フィード名 |
| url | string (unique) | フィードURL |
| last_fetched_at | timestamp nullable | 最終取得日時 |

### articles

| カラム | 型 | 説明 |
|---|---|---|
| id | bigint | PK |
| feed_id | bigint (FK) | feeds.id |
| url | string (unique) | 記事URL |
| title | string nullable | 記事タイトル |
| body | longtext nullable | 記事本文（未実装） |
| status | enum | pending / scraped / failed |
| published_at | timestamp nullable | 記事公開日時 |

## ローカル起動手順

```bash
# .env を用意
cp src/.env.example src/.env

# コンテナ起動
docker-compose up -d

# マイグレーション実行
docker-compose exec app php artisan migrate
```

## キュー

- **接続**: SQS (localstack)
- **キュー名**: `articles`
- **DLQ**: `articles-dlq`（3回失敗でデッドレターキューへ）
- **リトライ**: 最大3回 (`FetchFeedJob::$tries = 3`)

### キューの確認コマンド

```bash
# キュー一覧
docker-compose exec localstack awslocal sqs list-queues

# メッセージ数の確認
docker-compose exec localstack awslocal sqs get-queue-attributes \
  --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/articles \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

# DLQ のメッセージ数
docker-compose exec localstack awslocal sqs get-queue-attributes \
  --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/articles-dlq \
  --attribute-names ApproximateNumberOfMessages
```

| 属性 | 説明 |
|---|---|
| `ApproximateNumberOfMessages` | 未処理のメッセージ数 |
| `ApproximateNumberOfMessagesNotVisible` | Worker が処理中のメッセージ数 |

## 対応 RSS フォーマット

| フォーマット | リンク取得方法 |
|---|---|
| RSS 2.0 | `<link>` テキストノード |
| Atom | `<link href="...">` 属性 |
