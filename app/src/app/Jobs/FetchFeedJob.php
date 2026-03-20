<?php

namespace App\Jobs;

use App\Models\Article;
use App\Models\Feed;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class FetchFeedJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public function __construct(public readonly Feed $feed)
    {
    }

    public function handle(): void
    {
        Log::info("フィード取得開始: {$this->feed->url}");

        // フィードURLにHTTP GETリクエスト
        $response = Http::timeout(10)->get($this->feed->url);

        if ($response->failed()) {
            Log::warning("フィード取得失敗: {$this->feed->url}");
            return;
        }

        // レスポンスボディをXMLとしてパース
        $xml = simplexml_load_string($response->body());

        if ($xml === false) {
            Log::warning("RSSパース失敗: {$this->feed->url}");
            return;
        }

        // RSS2.0 は channel->item、Atom形式は entry に記事が入っている
        $items = $xml->channel->item ?? $xml->entry ?? [];

        foreach ($items as $item) {
            // RSS2.0 は <link>テキストノード、Atom は <link href="..."/>属性にURLが入っている
            $url = (string) ($item->link['href'] ?? $item->link ?? $item->id);

            if (empty($url)) {
                continue;
            }

            // Atom は <published>、RSS2.0 は <pubDate> に公開日が入っている
            $publishedAt = isset($item->pubDate)
                ? now()->parse((string) $item->pubDate)
                : (isset($item->published) ? now()->parse((string) $item->published) : null);

            // 同じURLの記事は重複登録しない
            Article::firstOrCreate(
                ['url' => $url],
                [
                    'feed_id'      => $this->feed->id,
                    'title'        => (string) $item->title,
                    'status'       => 'pending',
                    'published_at' => $publishedAt,
                ]
            );
        }

        // フィードの最終取得時刻を更新
        $this->feed->update(['last_fetched_at' => now()]);

        Log::info("フィード取得完了: {$this->feed->url}");
    }
}
