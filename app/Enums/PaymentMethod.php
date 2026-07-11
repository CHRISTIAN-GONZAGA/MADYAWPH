<?php

namespace App\Enums;

enum PaymentMethod: string
{
    case CASH = 'Cash';
    case GCASH = 'GCash';
    case PAYMAYA = 'PayMaya';
    case CREDIT_CARD = 'Credit Card';
    case MEMBER_POINTS = 'Member Points';
}
