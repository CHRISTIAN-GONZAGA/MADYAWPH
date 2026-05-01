import axios from 'axios';
import { router } from '@inertiajs/react';

export default function AmenityRequestList({ claims = [] }) {
    async function fulfillClaim(id) {
        try {
            await axios.patch(`/admin/amenity-claims/${id}/fulfill`);
            router.reload({ only: ['amenityClaims'] });
        } catch (_error) {
            alert('Unable to fulfill request right now.');
        }
    }

    return (
        <section className="bg-card border border-border rounded-2xl p-5">
            <h3 className="font-serif text-xl mb-4">Pending Amenity Requests</h3>
            {claims.length === 0 ? (
                <p className="text-muted-foreground text-sm">No pending requests.</p>
            ) : (
                <div className="space-y-3">
                    {claims.map((claim) => (
                        <div key={claim.id} className="border border-border rounded-xl p-4 flex items-center justify-between gap-3">
                            <div>
                                <p className="font-medium">{claim.amenityName ?? claim.amenityType}</p>
                                <p className="text-xs text-muted-foreground">
                                    Qty: {claim.quantity ?? 1} • Room {claim.roomNumber ?? '-'}
                                </p>
                            </div>
                            <button
                                onClick={() => fulfillClaim(claim.id)}
                                className="px-3 py-2 bg-primary text-primary-foreground rounded-full text-sm"
                            >
                                Fulfill
                            </button>
                        </div>
                    ))}
                </div>
            )}
        </section>
    );
}
