<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Article;
use Illuminate\Http\JsonResponse;

class ArticleController extends Controller
{
    public function index(): JsonResponse
    {
        $articles = Article::with('feed')
            ->latest()
            ->paginate(20);

        return response()->json($articles);
    }

    public function show(Article $article): JsonResponse
    {
        return response()->json($article->load('feed'));
    }
}
