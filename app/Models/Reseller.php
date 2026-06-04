<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use MongoDB\Laravel\Eloquent\Model;

class Reseller extends Model
{
    use BelongsToHotel, HasFactory;

    public const CATEGORIES = ['taxi', 'motorcycle', 'individual'];

    protected $fillable = [
        'hotel_id',
        'name',
        'phone',
        'email',
        'category',
        'id_document_url',
        'qr_token',
        'current_credits',
        'total_commissions_paid',
        'transactions',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'current_credits' => 'float',
            'total_commissions_paid' => 'float',
            'transactions' => 'array',
        ];
    }

    public function commissionPayments(): HasMany
    {
        return $this->hasMany(ResellerCommissionPayment::class);
    }
}
