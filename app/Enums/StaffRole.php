<?php

namespace App\Enums;

enum StaffRole: string
{
    case JANITOR = 'janitor';
    case RECEPTIONIST = 'receptionist';
    case MAINTENANCE = 'maintenance';
    case MANAGER = 'manager';
}
