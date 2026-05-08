<?php

namespace App\Models;

use Laravel\Sanctum\PersonalAccessToken as BasePersonalAccessToken;
use MongoDB\Laravel\Eloquent\DocumentModel;

class PersonalAccessToken extends BasePersonalAccessToken
{
    use DocumentModel;

    protected $connection = 'mongodb';

    protected $collection = 'personal_access_tokens';

    protected $primaryKey = '_id';

    protected $keyType = 'string';

    public $incrementing = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'abilities' => 'json',
            'last_used_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    /**
     * MongoDB tokens may be issued without an id prefix (e.g. "|plainToken").
     * Fallback to hash lookup so Sanctum can still authenticate them.
     */
    public static function findToken($token)
    {
        if (! is_string($token) || $token === '') {
            return null;
        }

        if (strpos($token, '|') === false) {
            return static::where('token', hash('sha256', $token))->first();
        }

        [$id, $plainTextToken] = explode('|', $token, 2);
        $hashed = hash('sha256', $plainTextToken);

        if ($id !== '') {
            $instance = static::query()->where('_id', $id)->first() ?? static::find($id);
            if ($instance && is_string($instance->token) && hash_equals($instance->token, $hashed)) {
                return $instance;
            }
        }

        return static::where('token', $hashed)->first();
    }
}