<?php

namespace App\Enums;

enum UserRole: string
{
    case CENTRAL_ADMIN = 'central_admin';
    case SUPER_ADMIN = 'super_admin';
    case OWNER = 'owner';
    case ADMIN = 'admin';
    case STAFF = 'staff';
}
