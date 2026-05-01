import { Head, useForm } from '@inertiajs/react';
import { motion } from 'motion/react';
import { useState } from 'react';
import BackButton from '../../Components/BackButton';

export default function RoomBooking({ hotel = null, category = null, rooms = [] }) {
    const hotelQuery = hotel?.id ? `?hotel=${encodeURIComponent(hotel.id)}` : '';
    const [actionMode, setActionMode] = useState('book');
    const { data, setData, post, processing, reset } = useForm({
        room_id: '',
        hotel_id: hotel?.id ?? '',
        guest_name: '',
        guest_email: '',
        guest_phone: '',
        check_in: '',
        check_out: '',
    });

    async function ensureCsrfCookie() {
        await window.axios.get('/sanctum/csrf-cookie');
    }

    async function submit(e) {
        e.preventDefault();
        await ensureCsrfCookie();
        post(actionMode === 'reserve' ? '/customer/reservations' : '/customer/bookings', {
            onSuccess: () => reset('guest_name', 'guest_email', 'guest_phone', 'check_in', 'check_out'),
        });
    }

    return (
        <div className="min-h-screen bg-background px-4 py-8">
            <Head title="Book a Room" />
            <div className="max-w-4xl mx-auto grid grid-cols-1 lg:grid-cols-2 gap-6">
                <motion.div initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }} className="bg-card border border-border rounded-xl p-4">
                    <div className="mb-3">
                        <BackButton fallback={`/customer/categories${hotelQuery}`} />
                    </div>
                    <h1 className="font-serif text-2xl mb-2">Available Rooms</h1>
                    <p className="text-sm text-muted-foreground mb-4">{hotel?.name} • {category?.name}</p>
                    <div className="space-y-2">
                        {rooms.map((room) => (
                            <button
                                key={room.id}
                                type="button"
                                onClick={() => setData('room_id', room.id)}
                                disabled={room.status !== 'available'}
                                className={`w-full text-left p-0 border rounded-lg overflow-hidden ${data.room_id === room.id ? 'border-primary bg-primary/5' : 'border-border'} ${room.status !== 'available' ? 'opacity-65 cursor-not-allowed' : ''}`}
                            >
                                <div className="flex gap-3">
                                    <img src={room.image_url} alt={`Room ${room.room_number}`} className="h-24 w-32 object-cover" />
                                    <div className="p-3 flex-1">
                                        <div className="flex items-center justify-between">
                                            <p className="font-medium">{room.display_name || `Room ${room.room_number ?? room.roomNumber ?? room.number}`}</p>
                                            <span className={`text-[11px] px-2 py-0.5 rounded-full capitalize ${
                                                room.status === 'available'
                                                    ? 'bg-emerald-100 text-emerald-700'
                                                    : room.status === 'booked'
                                                        ? 'bg-red-100 text-red-700'
                                                        : 'bg-amber-100 text-amber-700'
                                            }`}>
                                                {room.status}
                                            </span>
                                        </div>
                                        <p className="text-xs text-muted-foreground mt-1">{room.room_type} • ₱{Number(room.price_per_night ?? room.rate ?? 0).toLocaleString()} / night</p>
                                    </div>
                                </div>
                            </button>
                        ))}
                        {rooms.length === 0 && (
                            <p className="text-sm text-muted-foreground">No available rooms under this category right now. Please go back and pick another category.</p>
                        )}
                    </div>
                </motion.div>

                <motion.form initial={{ opacity: 0, x: 12 }} animate={{ opacity: 1, x: 0 }} onSubmit={submit} className="bg-card border border-border rounded-xl p-4 space-y-3">
                    <h2 className="font-serif text-xl">{actionMode === 'reserve' ? 'Reservation Details' : 'Booking Details'}</h2>
                    <input type="hidden" value={data.hotel_id} readOnly />
                    <div className="flex gap-2">
                        <button type="button" onClick={() => setActionMode('book')} className={`flex-1 px-3 py-2 rounded-lg text-sm ${actionMode === 'book' ? 'bg-primary text-primary-foreground' : 'border border-border'}`}>Book now</button>
                        <button type="button" onClick={() => setActionMode('reserve')} className={`flex-1 px-3 py-2 rounded-lg text-sm ${actionMode === 'reserve' ? 'bg-primary text-primary-foreground' : 'border border-border'}`}>Reserve for dates</button>
                    </div>
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Full Name" value={data.guest_name} onChange={(e) => setData('guest_name', e.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Email" type="email" value={data.guest_email} onChange={(e) => setData('guest_email', e.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Mobile Number (for SMS confirmation)" value={data.guest_phone} onChange={(e) => setData('guest_phone', e.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" type="date" value={data.check_in} onChange={(e) => setData('check_in', e.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" type="date" value={data.check_out} onChange={(e) => setData('check_out', e.target.value)} required />
                    <button disabled={processing || !data.room_id} className="w-full bg-primary text-primary-foreground rounded-full py-2.5 disabled:opacity-50">
                        {processing ? 'Submitting...' : actionMode === 'reserve' ? 'Reserve Room' : 'Book Now'}
                    </button>
                </motion.form>
            </div>
        </div>
    );
}
