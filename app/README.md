# SRE Playground - Article Collection App

RSSフィードから記事を収集するアプリケーション。

## アーキテクチャ

```
[Client]
   │
   ▼
[nginx :8080]
   │
   ▼
[app: PHP-FPM]  ──── POST /api/feeds ────▶ [SQS: localstack]
   │                                               │
   │                                               ▼
[MySQL]                                    [worker: queue:work]
[Redis]                                            │
                                                   ▼
                                           FetchFeedJob::handle()
                                                   │
                                                   ▼
                                           [MySQL: articles]
```

## サービス構成

| サービス | イメージ | 役割 |
|---|---|---|
| app | PHP 8.4-fpm-alpine | Laravel API サーバー (PHP-FPM) |
| worker | PHP 8.4-fpm-alpine | SQS キューワーカー |
| nginx | nginx:1.25-alpine | リバースプロキシ (:8080) |
| mysql | mysql:8.0 | データベース |
| redis | redis:7-alpine | セッション・キャッシュ |
| localstack | localstack:3 | AWS SQS エミュレーター |

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
```

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

## 対応 RSS フォーマット

| フォーマット | リンク取得方法 |
|---|---|
| RSS 2.0 | `<link>` テキストノード |
| Atom | `<link href="...">` 属性 |
