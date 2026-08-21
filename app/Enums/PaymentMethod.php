<?php

namespace App\Enums;

enum PaymentMethod: string
{
    case CASH = 'Cash';
    case GCASH = 'GCash';
    case E_WALLET = 'E-wallet';
    case PAYMAYA = 'PayMaya';
    case CREDIT_CARD = 'Credit Card';
    case BANK_TRANSFER = 'Bank Transfer';
    case MEMBER_POINTS = 'Member Points';
}
