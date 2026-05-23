<?php

namespace App\Providers;

use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        if (app()->environment('production')) {
            URL::forceScheme('https');
        }

        // Ensure Sanctum stores tokens in MongoDB when DB_CONNECTION=mongodb.
        Sanctum::usePersonalAccessTokenModel(\App\Models\PersonalAccessToken::class);

        foreach (['rooms', 'categories', 'chat'] as $dir) {
            $path = storage_path('app/public/'.$dir);
            if (! File::isDirectory($path)) {
                File::makeDirectory($path, 0755, true);
            }
        }
    }
}
