<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Article extends Model
{
    protected $fillable = ['feed_id', 'url', 'title', 'body', 'status', 'published_at'];

    protected $casts = [
        'published_at' => 'datetime',
    ];

    public function feed(): BelongsTo
    {
        return $this->belongsTo(Feed::class);
    }
}
