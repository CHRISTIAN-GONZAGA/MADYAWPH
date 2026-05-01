<?php

namespace App\Enums;

enum BookingStatus: string
{
    case RESERVED = 'reserved';
    case BOOKED = 'booked';
    case CONFIRMED = 'confirmed';
    case CANCELLED = 'cancelled';
    case COMPLETED = 'completed';
}
