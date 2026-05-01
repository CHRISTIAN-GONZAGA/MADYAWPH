<?php

namespace App\Enums;

enum BookingSource: string
{
    case KIOSK = 'kiosk';
    case WEB = 'web';
    case ADMIN = 'admin';
}
