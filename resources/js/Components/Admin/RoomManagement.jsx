import { useMemo, useState } from 'react';
import axios from 'axios';
import { router } from '@inertiajs/react';

export default function RoomManagement({ rooms = [], allRooms = [] }) {
    const [updatingRoomId, setUpdatingRoomId] = useState(null);
    const [selectedRoom, setSelectedRoom] = useState(null);
    const [expandedCategory, setExpandedCategory] = useState(null);
    const [chargeAmount, setChargeAmount] = useState('');
    const [chargeReason, setChargeReason] = useState('');
    const [chargeRoomId, setChargeRoomId] = useState('');
    const [transferRoomId, setTransferRoomId] = useState('');
    const [reservationDate, setReservationDate] = useState('');
    const grouped = useMemo(() => {
        return rooms.reduce((acc, room) => {
            const key = room.category_name ?? room.room_type?.value ?? room.room_type ?? room.category ?? 'Uncategorized';
            if (!acc[key]) acc[key] = [];
            acc[key].push(room);
            return acc;
        }, {});
    }, [rooms]);

    async function updateRoomStatus(roomId, status) {
        setUpdatingRoomId(roomId);
        try {
            await axios.patch(`/admin/rooms/${roomId}/status`, { status });
            router.reload({ only: ['rooms'] });
        } catch (_error) {
            alert('Unable to update room status.');
        } finally {
            setUpdatingRoomId(null);
        }
    }

    function statusClasses(status) {
        if (status === 'available') return 'bg-emerald-100 text-emerald-700';
        if (status === 'booked') return 'bg-red-100 text-red-700';
        if (status === 'reserved') return 'bg-blue-100 text-blue-700';
        return 'bg-amber-100 text-amber-700';
    }

    async function addCharge(type) {
        if (!selectedRoom?.latest_booking?.id) {
            alert('Select a booked room first.');
            return;
        }
        const amount = Number(chargeAmount);
        if (!Number.isFinite(amount) || amount < 0) {
            alert('Enter a valid amount.');
            return;
        }
        await axios.post('/api/billing/charges', {
            booking_id: selectedRoom.latest_booking.id,
            room_id: chargeRoomId || selectedRoom.id,
            type,
            label: chargeReason || type,
            amount,
            quantity: 1,
            is_manual: true,
        });
        setChargeAmount('');
        setChargeReason('');
        router.reload({ only: ['rooms', 'activityLogs'] });
    }

    async function createReservation() {
        if (!reservationDate) {
            alert('Pick a reservation date.');
            return;
        }
        await axios.post('/api/reservations/external', {
            source: 'website-preconnect',
            external_reference: `WEB-${Date.now()}`,
            guest_name: 'Website Guest',
            check_in_date: reservationDate,
            check_out_date: reservationDate,
        });
        alert('Reservation placeholder captured for website sync.');
    }

    async function transferRoom() {
        if (!selectedRoom?.latest_booking?.id || !transferRoomId) {
            alert('Choose destination room first.');
            return;
        }
        await axios.post('/api/room-transfers', {
            booking_id: selectedRoom.latest_booking.id,
            from_room_id: selectedRoom.id,
            to_room_id: transferRoomId,
            reason: 'Admin transfer',
        });
        router.reload({ only: ['rooms', 'activityLogs', 'transfers'] });
        setTransferRoomId('');
        setSelectedRoom(null);
    }

    return (
        <section className="bg-card border border-border rounded-2xl p-5">
            <h3 className="font-serif text-xl mb-4">Room Management</h3>
            {Object.keys(grouped).length === 0 ? (
                <p className="text-muted-foreground text-sm">No rooms available.</p>
            ) : (
                <div className="space-y-4">
                    {Object.entries(grouped).map(([category, roomList]) => (
                        <div key={category}>
                            <button type="button" onClick={() => setExpandedCategory((prev) => (prev === category ? null : category))} className="w-full text-left font-medium mb-2 rounded-lg border border-border px-3 py-2 bg-background">
                                {category} ({roomList.length})
                            </button>
                            {expandedCategory === category && (
                                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                                {roomList.map((room) => (
                                    <div key={room.id} className="border border-border rounded-lg overflow-hidden text-sm bg-background">
                                        <div role="button" tabIndex={0} onClick={() => setSelectedRoom(room)} onKeyDown={(e) => { if (e.key === 'Enter') setSelectedRoom(room); }} className="p-3 text-left w-full hover:bg-card/60 transition-colors cursor-pointer">
                                            <div className="flex items-center justify-between gap-2">
                                                <p className="font-medium">Room {room.room_number ?? room.roomNumber ?? room.number}</p>
                                                <span className={`text-[11px] px-2 py-0.5 rounded-full capitalize ${statusClasses(room.status?.value ?? room.status ?? 'available')}`}>
                                                    {room.status?.value ?? room.status ?? 'available'}
                                                </span>
                                            </div>
                                            {(room.current_access_code && (room.status?.value ?? room.status) === 'booked') && (
                                                <p className="mt-2 text-xs text-primary">
                                                    Guest Password: <span className="font-semibold tracking-wider">{room.current_access_code}</span>
                                                </p>
                                            )}
                                            <div className="mt-2 flex items-center gap-2">
                                                <label className="text-xs text-muted-foreground">Set:</label>
                                                <select
                                                    onClick={(e) => e.stopPropagation()}
                                                    disabled={updatingRoomId === room.id}
                                                    defaultValue={room.status?.value ?? room.status ?? 'available'}
                                                    onChange={(e) => updateRoomStatus(room.id, e.target.value)}
                                                    className="border border-border rounded px-2 py-1 text-xs bg-card"
                                                >
                                                    <option value="available">Available</option>
                                                    <option value="booked">Booked</option>
                                                    <option value="maintenance">Maintenance</option>
                                                    <option value="reserved">Reserved</option>
                                                </select>
                                            </div>
                                        </div>
                                    </div>
                                ))}
                                </div>
                            )}
                        </div>
                    ))}
                </div>
            )}

            <div className="mt-4 rounded-xl border border-border p-3 bg-background">
                <p className="text-sm font-medium">Reservation (for website integration)</p>
                <div className="mt-2 flex gap-2">
                    <input type="date" value={reservationDate} onChange={(event) => setReservationDate(event.target.value)} className="border border-border rounded px-2 py-1 text-sm" />
                    <button type="button" onClick={createReservation} className="px-3 py-1 rounded bg-primary text-primary-foreground text-sm">Save reservation date</button>
                </div>
            </div>

            {selectedRoom && (
                <div className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center" onClick={() => setSelectedRoom(null)}>
                    <div className="w-full max-w-lg rounded-2xl border border-border bg-card p-5" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center justify-between mb-4">
                            <h4 className="font-serif text-xl">Room {selectedRoom.room_number ?? selectedRoom.roomNumber ?? selectedRoom.number}</h4>
                            <button type="button" onClick={() => setSelectedRoom(null)} className="text-sm text-muted-foreground">Close</button>
                        </div>
                        {selectedRoom.latest_booking ? (
                            <div className="space-y-2 text-sm">
                                <p><span className="text-muted-foreground">Booking Ref:</span> {selectedRoom.latest_booking.booking_reference}</p>
                                <p><span className="text-muted-foreground">Guest:</span> {selectedRoom.latest_booking.guest_name}</p>
                                <p><span className="text-muted-foreground">Email:</span> {selectedRoom.latest_booking.guest_email ?? '-'}</p>
                                <p><span className="text-muted-foreground">Phone:</span> {selectedRoom.latest_booking.guest_phone ?? '-'}</p>
                                <p><span className="text-muted-foreground">Check-in:</span> {selectedRoom.latest_booking.check_in_date ?? '-'}</p>
                                <p><span className="text-muted-foreground">Check-out:</span> {selectedRoom.latest_booking.check_out_date ?? '-'}</p>
                                <p><span className="text-muted-foreground">Room Bill:</span> PHP {Number(selectedRoom.latest_booking.total_amount ?? 0).toLocaleString()}</p>
                                <p><span className="text-muted-foreground">Booked At:</span> {selectedRoom.latest_booking.created_at ? new Date(selectedRoom.latest_booking.created_at).toLocaleString() : '-'}</p>
                                <div className="pt-2">
                                    <p className="text-muted-foreground">Charges</p>
                                    <ul className="text-xs space-y-1 mt-1">
                                        {(selectedRoom.charges ?? []).map((charge) => (
                                            <li key={charge.id} className="flex justify-between">
                                                <span>{charge.label}</span>
                                                <span>PHP {Number(charge.amount ?? 0).toLocaleString()}</span>
                                            </li>
                                        ))}
                                    </ul>
                                    <p className="text-sm font-medium mt-2">
                                        Total bill: PHP {Number((selectedRoom.latest_booking.total_amount ?? 0) + (selectedRoom.charges ?? []).reduce((sum, charge) => sum + Number(charge.amount ?? 0), 0)).toLocaleString()}
                                    </p>
                                </div>
                                <div className="pt-3 border-t border-border space-y-2">
                                    <p className="font-medium">Add Charges / Shop / Violations</p>
                                    <select value={chargeRoomId} onChange={(event) => setChargeRoomId(event.target.value)} className="w-full border border-border rounded px-2 py-1 text-xs bg-background">
                                        <option value="">Charge this room (default)</option>
                                        {allRooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number ?? room.number}</option>)}
                                    </select>
                                    <div className="flex gap-2">
                                        <input value={chargeAmount} onChange={(event) => setChargeAmount(event.target.value)} type="number" min="0" className="flex-1 border border-border rounded px-2 py-1 text-xs bg-background" placeholder="Amount" />
                                        <input value={chargeReason} onChange={(event) => setChargeReason(event.target.value)} className="flex-1 border border-border rounded px-2 py-1 text-xs bg-background" placeholder="Reason (custom/shop/extra person)" />
                                    </div>
                                    <div className="flex gap-2 flex-wrap">
                                        <button type="button" onClick={() => addCharge('early-checkin')} className="px-2 py-1 text-xs rounded bg-primary text-primary-foreground">Early/Late Fee</button>
                                        <button type="button" onClick={() => addCharge('extra-person')} className="px-2 py-1 text-xs rounded border border-border">Extra Person</button>
                                        <button type="button" onClick={() => addCharge('shop')} className="px-2 py-1 text-xs rounded border border-border">Shop Charge</button>
                                        <button type="button" onClick={() => addCharge('custom')} className="px-2 py-1 text-xs rounded border border-border">Custom Fee</button>
                                    </div>
                                </div>
                                <div className="pt-3 border-t border-border space-y-2">
                                    <p className="font-medium">Transfer Guest Room</p>
                                    <div className="flex gap-2">
                                        <select value={transferRoomId} onChange={(event) => setTransferRoomId(event.target.value)} className="flex-1 border border-border rounded px-2 py-1 text-xs bg-background">
                                            <option value="">Select destination room</option>
                                            {allRooms.filter((room) => room.id !== selectedRoom.id).map((room) => (
                                                <option key={room.id} value={room.id}>Room {room.room_number ?? room.number}</option>
                                            ))}
                                        </select>
                                        <button type="button" onClick={transferRoom} className="px-3 py-1 text-xs rounded bg-primary text-primary-foreground">Transfer</button>
                                    </div>
                                </div>
                            </div>
                        ) : (
                            <p className="text-sm text-muted-foreground">No booking data for this room yet.</p>
                        )}
                    </div>
                </div>
            )}
        </section>
    );
}
