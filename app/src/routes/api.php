<?php

use App\Http\Controllers\Api\ArticleController;
use App\Http\Controllers\Api\FeedController;
use Illuminate\Support\Facades\Route;

Route::get('/feeds', [FeedController::class, 'index']);
Route::post('/feeds', [FeedController::class, 'store']);

Route::get('/articles', [ArticleController::class, 'index']);
Route::get('/articles/{article}', [ArticleController::class, 'show']);
