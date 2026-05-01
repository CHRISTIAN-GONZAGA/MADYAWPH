<?php

namespace App\Enums;

enum RoomStatus: string
{
    case AVAILABLE = 'available';
    case BOOKED = 'booked';
    case MAINTENANCE = 'maintenance';
    case RESERVED = 'reserved';
}
