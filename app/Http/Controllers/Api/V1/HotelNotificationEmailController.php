<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\User;
use App\Support\HotelNotificationRecipients;
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
            $rules['frontdesk_user_id'] = ['sometimes', 'nullable', 'string', 'max:64'];
            $rules['frontdesk_email'] = ['sometimes', 'nullable', 'email', 'max:255'];
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

        if ($isSuper && (
            array_key_exists('frontdesk_user_id', $validated)
            || array_key_exists('frontdesk_email', $validated)
        )) {
            $this->updateFrontdeskNotification($hotel, $hotelId, $validated);
        }

        $hotel->refresh();
        $adminUser = $this->primaryAdminUser($hotelId);

        return response()->json($this->payload($hotel, $user->fresh() ?? $user, $adminUser));
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function updateFrontdeskNotification(Hotel $hotel, string $hotelId, array $validated): void
    {
        $selectedId = array_key_exists('frontdesk_user_id', $validated)
            ? trim((string) ($validated['frontdesk_user_id'] ?? ''))
            : trim((string) ($hotel->frontdesk_notification_user_id ?? ''));

        if ($selectedId === '') {
            $hotel->forceFill(['frontdesk_notification_user_id' => null])->save();

            return;
        }

        $frontdesk = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($selectedId);

        if ($frontdesk === null || $frontdesk->roleValue() !== UserRole::FRONTDESK->value) {
            throw ValidationException::withMessages([
                'frontdesk_user_id' => ['Select a valid front desk account.'],
            ]);
        }

        $hotel->forceFill(['frontdesk_notification_user_id' => (string) $frontdesk->id])->save();

        if (array_key_exists('frontdesk_email', $validated)) {
            $email = strtolower(trim((string) ($validated['frontdesk_email'] ?? '')));
            if ($email === '') {
                throw ValidationException::withMessages([
                    'frontdesk_email' => ['Enter a Gmail address for the selected front desk account.'],
                ]);
            }
            if (! HotelNotificationRecipients::isDeliverable($email)) {
                throw ValidationException::withMessages([
                    'frontdesk_email' => ['Use a real Gmail (or other deliverable) address, not a @hotel.local login.'],
                ]);
            }
            PortalAccountSupport::assertEmailAvailable($email, (string) $frontdesk->id);
            $frontdesk->forceFill(['email' => $email])->save();
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function payload(Hotel $hotel, User $currentUser, ?User $adminUser): array
    {
        $role = $currentUser->roleValue();
        $hotelId = (string) $hotel->id;
        $frontdeskUsers = $this->frontdeskUsers($hotelId);
        $selectedId = trim((string) ($hotel->frontdesk_notification_user_id ?? ''));
        $selected = collect($frontdeskUsers)->firstWhere('id', $selectedId);
        if ($selected === null && $frontdeskUsers !== []) {
            $selected = $frontdeskUsers[0];
            $selectedId = (string) ($selected['id'] ?? '');
        }

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
            'can_edit_frontdesk_email' => $role === UserRole::SUPER_ADMIN->value,
            'frontdesk_user_id' => $selectedId,
            'frontdesk_email' => strtolower(trim((string) ($selected['email'] ?? ''))),
            'frontdesk_users' => $frontdeskUsers,
        ];
    }

    /**
     * @return list<array{id: string, name: string, email: string}>
     */
    private function frontdeskUsers(string $hotelId): array
    {
        return User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('name')
            ->get()
            ->filter(fn (User $user) => $user->roleValue() === UserRole::FRONTDESK->value)
            ->map(fn (User $user) => [
                'id' => (string) $user->id,
                'name' => (string) ($user->name ?? ''),
                'email' => strtolower(trim((string) ($user->email ?? ''))),
            ])
            ->values()
            ->all();
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
