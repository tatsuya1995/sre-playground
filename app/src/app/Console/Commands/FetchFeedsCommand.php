<?php

namespace App\Console\Commands;

use App\Jobs\FetchFeedJob;
use App\Models\Feed;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('feeds:fetch')]
#[Description('全フィードの記事取得ジョブをSQSに送信する')]
class FetchFeedsCommand extends Command
{
    public function handle(): void
    {
        $feeds = Feed::all();

        foreach ($feeds as $feed) {
            FetchFeedJob::dispatch($feed);
            $this->info("ジョブ送信: {$feed->url}");
        }

        $this->info("合計 {$feeds->count()} 件のジョブを送信しました。");
    }
}
