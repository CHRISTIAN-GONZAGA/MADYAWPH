<?php

namespace App\Enums;

enum RoomStatus: string
{
    case AVAILABLE = 'available';
    case BOOKED = 'booked';
    case CHECKED_IN = 'checked_in';
    case CHECKED_OUT = 'checked_out';
    case MAINTENANCE = 'maintenance';
    case RESERVED = 'reserved';
}
