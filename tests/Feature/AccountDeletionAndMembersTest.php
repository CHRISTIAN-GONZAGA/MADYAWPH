<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use App\Services\MemberSubscriptionApprovalService;
use Tests\TestCase;

class AccountDeletionAndMembersTest extends TestCase
{
    public function test_member_can_request_deletion_and_central_admin_can_approve(): void
    {
        $member = $this->approvedMember('del_member', 'Delete Me');
        $token = $this->memberToken('del_member', 'pass1234');
        $central = app(CentralAdminAccountService::class)->ensureUser();

        $this->withToken($token)
            ->postJson('/api/v1/member/request-deletion', ['notes' => 'Please close my account'])
            ->assertCreated()
            ->assertJsonPath('ok', true);

        $this->withToken($token)
            ->getJson('/api/v1/member/dashboard')
            ->assertOk()
            ->assertJsonPath('member.deletion_requested', true);

        $listed = $this->actingAs($central)
            ->getJson('/api/v1/platform/deletion-requests')
            ->assertOk()
            ->json('data');
        $this->assertIsArray($listed);
        $row = collect($listed)->first(
            fn ($item) => is_array($item) && ($item['username'] ?? '') === 'del_member'
        );
        $this->assertIsArray($row);

        $this->actingAs($central)
            ->postJson('/api/v1/platform/deletion-requests/'.$row['id'].'/approve')
            ->assertOk();

        $this->assertNull(MemberSubscriptionRequest::query()->find($member->id));
        $this->withToken($token)
            ->getJson('/api/v1/member/dashboard')
            ->assertUnauthorized();
    }

    public function test_hotel_admin_can_request_deletion_and_central_admin_can_approve(): void
    {
        $hotel = Hotel::create(['name' => 'Close Me Inn', 'location' => 'City', 'owner_email' => 'close@test.local']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'closeadmin',
            'email' => 'closeadmin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $central = app(CentralAdminAccountService::class)->ensureUser();

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/account/deletion-request', ['notes' => 'Shutting down'])
            ->assertCreated()
            ->assertJsonPath('already_pending', false);

        $this->actingAs($admin)
            ->getJson('/api/v1/admin/account/deletion-request')
            ->assertOk()
            ->assertJsonPath('deletion_requested', true);

        $listed = collect($this->actingAs($central)
            ->getJson('/api/v1/platform/deletion-requests')
            ->assertOk()
            ->json('data') ?? []);
        $row = $listed->first(
            fn ($item) => is_array($item) && ($item['hotel_name'] ?? '') === 'Close Me Inn'
        );
        $this->assertIsArray($row);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/account/deletion-request')
            ->assertOk()
            ->assertJsonPath('already_pending', true);

        $this->actingAs($central)
            ->postJson('/api/v1/platform/deletion-requests/'.$row['id'].'/approve')
            ->assertOk();

        $this->assertNull(Hotel::withoutGlobalScopes()->find($hotel->id));
        $this->assertNull(User::withoutGlobalScopes()->find($admin->id));
    }

    public function test_front_desk_cannot_request_hotel_deletion(): void
    {
        $hotel = Hotel::create(['name' => 'Desk Hotel', 'location' => 'City']);
        $desk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'desk1',
            'email' => 'desk1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        $this->actingAs($desk)
            ->postJson('/api/v1/admin/account/deletion-request')
            ->assertForbidden();
    }

    public function test_central_admin_can_list_search_grant_points_and_delete_members(): void
    {
        $keep = $this->approvedMember('keep_mem', 'Keep Member');
        $this->approvedMember('find_mem', 'Search Target');
        $central = app(CentralAdminAccountService::class)->ensureUser();

        $all = $this->actingAs($central)
            ->getJson('/api/v1/platform/members')
            ->assertOk()
            ->json('data');
        $this->assertGreaterThanOrEqual(2, count($all ?? []));

        $found = collect($this->actingAs($central)
            ->getJson('/api/v1/platform/members?q=Search Target')
            ->assertOk()
            ->json('data') ?? []);
        $this->assertTrue($found->contains(fn ($r) => ($r['username'] ?? '') === 'find_mem'));
        $this->assertFalse($found->contains(fn ($r) => ($r['username'] ?? '') === 'keep_mem'));

        $this->actingAs($central)
            ->postJson('/api/v1/platform/members/'.(string) $keep->id.'/points', [
                'points' => 250,
                'reason' => 'Goodwill',
            ])
            ->assertOk()
            ->assertJsonPath('points_added', 250)
            ->assertJsonPath('points_balance', 250);

        $keep->refresh();
        $this->assertSame(250.0, (float) $keep->points_balance);

        $this->actingAs($central)
            ->deleteJson('/api/v1/platform/members/'.(string) $keep->id)
            ->assertOk();
        $this->assertNull(MemberSubscriptionRequest::query()->find($keep->id));
    }

    public function test_hotel_admin_cannot_list_platform_members(): void
    {
        $hotel = Hotel::create(['name' => 'No Access Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'noaccess',
            'email' => 'noaccess@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $this->actingAs($admin)
            ->getJson('/api/v1/platform/members')
            ->assertForbidden();
    }

    private function approvedMember(string $username, string $name): MemberSubscriptionRequest
    {
        $row = MemberSubscriptionRequest::create([
            'full_name' => $name,
            'email' => $username.'@example.com',
            'phone' => '09170000000',
            'username' => $username,
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-'.$username,
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $reviewer = User::factory()->create();

        return app(MemberSubscriptionApprovalService::class)->approve($row, $reviewer);
    }

    private function memberToken(string $username, string $password): string
    {
        $login = $this->postJson('/api/v1/member/login', [
            'username' => $username,
            'password' => $password,
        ])->assertOk();

        return (string) $login->json('member_token');
    }
}
