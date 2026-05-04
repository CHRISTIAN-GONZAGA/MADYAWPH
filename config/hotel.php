<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Strict tenant Eloquent scoping
    |--------------------------------------------------------------------------
    |
    | When true, models using BelongsToHotel apply an impossible constraint if
    | no active hotel context was bound for the request (fail-closed). Keep
    | false locally if you run artisan/seeders without binding a tenant.
    |
    */
    'strict_tenant_scoping' => (bool) env('STRICT_TENANT_SCOPING', false),

];
