<?php

namespace Tests\Feature;

use App\Support\ChatAttachmentUrl;
use App\Support\PublicUploadStorage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PublicUploadStorageTest extends TestCase
{
    public function test_uploads_use_uploads_disk_by_default(): void
    {
        Storage::fake('uploads');
        Config::set('filesystems.uploads_disk', 'uploads');

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $file = UploadedFile::fake()->createWithContent('room.png', $png);

        $path = PublicUploadStorage::store($file, 'rooms');
        $this->assertStringStartsWith('rooms/', $path);
        Storage::disk('uploads')->assertExists($path);

        $url = ChatAttachmentUrl::fromStoredUrl($path);
        $this->assertNotNull($url);
        $this->assertStringContainsString('/api/v1/chat/media', (string) $url);
    }

    public function test_legacy_public_files_remain_readable_when_using_uploads_disk(): void
    {
        Storage::fake('uploads');
        Storage::fake('public');
        Config::set('filesystems.uploads_disk', 'uploads');

        Storage::disk('public')->put('categories/legacy.jpg', 'legacy');

        $this->assertTrue(PublicUploadStorage::exists('categories/legacy.jpg'));
        $url = ChatAttachmentUrl::fromStoredUrl('categories/legacy.jpg');
        $this->assertStringContainsString('/api/v1/chat/media', (string) $url);

        $this->get('/api/v1/chat/media?f='.rawurlencode('categories/legacy.jpg'))->assertOk();
    }

    public function test_uploads_can_still_use_s3_when_configured(): void
    {
        Storage::fake('s3');
        Config::set('filesystems.uploads_disk', 's3');
        Config::set('filesystems.disks.s3.bucket', 'test-bucket');
        Config::set('filesystems.disks.s3.key', 'key');
        Config::set('filesystems.disks.s3.secret', 'secret');
        Config::set('filesystems.disks.s3.region', 'ap-southeast-1');

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $file = UploadedFile::fake()->createWithContent('room.png', $png);

        $path = PublicUploadStorage::store($file, 'rooms');
        Storage::disk('s3')->assertExists($path);
    }
}
