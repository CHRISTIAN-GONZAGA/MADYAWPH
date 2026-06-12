<?php

namespace App\Console\Commands;

use App\Support\PublicUploadStorage;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class EnsurePersistentUploadsCommand extends Command
{
    protected $signature = 'uploads:ensure-persistent';

    protected $description = 'Prepare Render persistent upload disk and migrate legacy ephemeral files';

    public function handle(): int
    {
        PublicUploadStorage::ensureUploadRootExists();
        PublicUploadStorage::ensureUploadSubdirectoriesExist();

        $migrated = PublicUploadStorage::migrateEphemeralUploadsIfNeeded();

        if ($migrated > 0) {
            $this->info("Migrated {$migrated} upload file(s) to persistent storage.");
        }

        if (app()->environment('production') && ! PublicUploadStorage::usingPersistentRoot()) {
            $message = 'FILESYSTEM_UPLOAD_ROOT is not set to a Render persistent disk — '
                .'uploads will be lost on redeploy. Attach a disk at /var/data/uploads and set FILESYSTEM_UPLOAD_ROOT.';
            $this->warn($message);
            Log::warning($message);
        }

        return self::SUCCESS;
    }
}
