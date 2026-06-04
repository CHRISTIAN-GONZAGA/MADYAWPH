<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use MongoDB\Laravel\Eloquent\Model;

class ResellerCommissionPayment extends Model
{
    use BelongsToHotel, HasFactory;

    public $timestamps = false;

    protected $fillable = [
        'hotel_id',
        'reseller_id',
        'reseller_name',
        'reseller_category',
        'amount',
        'note',
        'balance_before',
        'balance_after',
        'paid_by_user_id',
        'paid_by_user_name',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'balance_before' => 'float',
            'balance_after' => 'float',
            'created_at' => 'datetime',
        ];
    }

    public function reseller(): BelongsTo
    {
        return $this->belongsTo(Reseller::class);
    }
}
