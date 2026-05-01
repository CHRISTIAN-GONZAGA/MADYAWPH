<?php

namespace App\Models;

use Laravel\Sanctum\PersonalAccessToken as BasePersonalAccessToken;
use MongoDB\Laravel\Eloquent\DocumentModel;

class PersonalAccessToken extends BasePersonalAccessToken
{
    use DocumentModel;

    protected $connection = 'mongodb';
    protected $collection = 'personal_access_tokens';
    protected $keyType = 'string';
}

