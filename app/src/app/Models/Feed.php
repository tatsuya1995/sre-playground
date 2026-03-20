<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Feed extends Model
{
    protected $fillable = ['name', 'url', 'last_fetched_at'];

    protected $casts = [
        'last_fetched_at' => 'datetime',
    ];

    public function articles(): HasMany
    {
        return $this->hasMany(Article::class);
    }
}
