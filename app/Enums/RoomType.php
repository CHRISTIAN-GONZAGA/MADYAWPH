<?php

namespace App\Enums;

enum RoomType: string
{
    case SINGLE = 'Single';
    case DOUBLE = 'Double';
    case SUITE = 'Suite';
    case DELUXE = 'Deluxe';
}
