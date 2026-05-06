<?php

namespace App\Models;

use App\Casts\SanctumAbilities;
use Laravel\Sanctum\PersonalAccessToken as BasePersonalAccessToken;
use MongoDB\Laravel\Eloquent\DocumentModel;

class PersonalAccessToken extends BasePersonalAccessToken
{
    use DocumentModel;

    protected $connection = 'mongodb';

    protected $collection = 'personal_access_tokens';

    protected $keyType = 'string';

    protected function casts(): array
    {
        return [
            'abilities' => SanctumAbilities::class,
            'last_used_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }
}
