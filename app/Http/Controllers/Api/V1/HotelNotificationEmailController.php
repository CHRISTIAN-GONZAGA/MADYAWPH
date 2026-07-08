<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\User;
use App\Support\PortalAccountSupport;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class HotelNotificationEmailController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        $hotelId = (string) $user->hotel_id;
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $adminUser = $this->primaryAdminUser($hotelId);

        return response()->json($this->payload($hotel, $user, $adminUser));
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $role = $user->roleValue();
        if (! in_array($role, [UserRole::ADMIN->value, UserRole::SUPER_ADMIN->value], true)) {
            return response()->json(['message' => 'Forbidden.'], 403);
        }

        $isSuper = $role === UserRole::SUPER_ADMIN->value;
        $rules = [
            'owner_email' => ['sometimes', 'required', 'email', 'max:255'],
            'my_email' => ['sometimes', 'required', 'email', 'max:255'],
        ];
        if ($isSuper) {
            $rules['admin_email'] = ['sometimes', 'required', 'email', 'max:255'];
        }
        $validated = $request->validate($rules);

        $hotelId = (string) $user->hotel_id;
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        if (array_key_exists('owner_email', $validated)) {
            $hotel->forceFill([
                'owner_email' => strtolower(trim((string) $validated['owner_email'])),
            ])->save();
        }

        if (array_key_exists('my_email', $validated)) {
            $email = strtolower(trim((string) $validated['my_email']));
            PortalAccountSupport::assertEmailAvailable($email, (string) $user->id);
            $user->forceFill(['email' => $email])->save();
            $user->refresh();
        }

        if ($isSuper && array_key_exists('admin_email', $validated)) {
            $adminUser = $this->primaryAdminUser($hotelId);
            if ($adminUser === null) {
                throw ValidationException::withMessages([
                    'admin_email' => ['No administrator account exists for this hotel yet.'],
                ]);
            }
            $email = strtolower(trim((string) $validated['admin_email']));
            PortalAccountSupport::assertEmailAvailable($email, (string) $adminUser->id);
            $adminUser->forceFill(['email' => $email])->save();
        }

        $hotel->refresh();
        $adminUser = $this->primaryAdminUser($hotelId);

        return response()->json($this->payload($hotel, $user->fresh() ?? $user, $adminUser));
    }

    /**
     * @return array<string, mixed>
     */
    private function payload(Hotel $hotel, User $currentUser, ?User $adminUser): array
    {
        $role = $currentUser->roleValue();

        return [
            'owner_email' => strtolower(trim((string) ($hotel->owner_email ?? ''))),
            'my_email' => strtolower(trim((string) ($currentUser->email ?? ''))),
            'my_role' => $role,
            'admin_email' => strtolower(trim((string) ($adminUser?->email ?? ''))),
            'can_edit_admin_email' => $role === UserRole::SUPER_ADMIN->value,
            'can_edit_owner_email' => in_array($role, [
                UserRole::ADMIN->value,
                UserRole::SUPER_ADMIN->value,
            ], true),
        ];
    }

    private function primaryAdminUser(string $hotelId): ?User
    {
        return User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('created_at')
            ->get()
            ->first(fn (User $user) => $user->roleValue() === UserRole::ADMIN->value);
    }
}
