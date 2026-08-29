<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PublicPaymentQrRouteTest extends TestCase
{
    public function test_public_payment_qr_route_serves_the_file(): void
    {
        Storage::fake('uploads');
        Config::set('filesystems.uploads_disk', 'uploads');

        $filename = '5w0Cmr4k314SP7xT1qW0kyB84wrkdWeEeO6iKhhF.jpg';
        Storage::disk('uploads')->put('payment-qr/'.$filename, 'fake-qr-bytes');

        $this->get('/uploads/payment-qr/'.$filename)
            ->assertOk()
            ->assertHeader('Content-Type', 'image/jpeg')
            ->assertHeader('Access-Control-Allow-Origin', '*');
    }

    public function test_legacy_chat_media_url_still_serves_payment_qr(): void
    {
        Storage::fake('uploads');
        Config::set('filesystems.uploads_disk', 'uploads');

        $filename = 'legacyQrFile.jpg';
        Storage::disk('uploads')->put('payment-qr/'.$filename, 'fake-qr-bytes');

        $this->get('/api/v1/chat/media?f='.rawurlencode('payment-qr/'.$filename))
            ->assertOk();
    }

    public function test_public_payment_qr_route_rejects_path_traversal_and_unknown_files(): void
    {
        Storage::fake('uploads');
        Config::set('filesystems.uploads_disk', 'uploads');

        $this->get('/uploads/payment-qr/../rooms/secret.jpg')->assertNotFound();
        $this->get('/uploads/payment-qr/missing.jpg')->assertNotFound();
        $this->get('/uploads/payment-qr/not-an-image.txt')->assertNotFound();
    }
}
