<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Jobs\FetchFeedJob;
use App\Models\Feed;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FeedController extends Controller
{
    public function index(): JsonResponse
    {
        $feeds = Feed::latest()->get();

        return response()->json($feeds);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'url'  => 'required|url|unique:feeds,url',
        ]);

        $feed = Feed::create($validated);

        // ジョブをSQSキューへ投げる
        FetchFeedJob::dispatch($feed);

        return response()->json($feed, 201);
    }
}
