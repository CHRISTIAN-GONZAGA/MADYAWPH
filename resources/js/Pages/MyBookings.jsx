import { Head } from '@inertiajs/react';
import { useEffect, useState } from 'react';
import axios from 'axios';
import { Calendar, Mail } from 'lucide-react';
import BackButton from '../Components/BackButton';
import Card from '../Components/Card';
import Input from '../Components/Input';
import Button from '../Components/Button';

export default function MyBookings() {
    const [hotels, setHotels] = useState([]);
    const [hotelId, setHotelId] = useState('');
    const [guestEmail, setGuestEmail] = useState('');
    const [guestPhone, setGuestPhone] = useState('');
    const [bookings, setBookings] = useState([]);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        axios.get('/api/hotels')
            .then((response) => setHotels(response.data ?? []))
            .catch(() => setHotels([]));
    }, []);

    async function lookupBookings() {
        if (!hotelId || (!guestEmail && !guestPhone)) {
            alert('Please select a hotel and enter email or phone.');
            return;
        }
        setLoading(true);
        try {
            const response = await axios.get('/api/my-bookings', {
                params: {
                    hotel_id: hotelId,
                    guest_email: guestEmail || undefined,
                    guest_phone: guestPhone || undefined,
                },
            });
            setBookings(response.data ?? []);
        } catch (_error) {
            alert('Unable to fetch bookings.');
        } finally {
            setLoading(false);
        }
    }

    return (
        <>
            <Head title="My bookings" />
            <div className="min-h-screen bg-linen px-4 py-10">
                <div className="mx-auto max-w-lg">
                    <BackButton fallback="/login" />
                    <h1 className="font-serif text-3xl font-bold text-foreground">My bookings</h1>
                    <p className="mt-2 text-muted-foreground">Look up upcoming and past stays with email or phone.</p>

                    <Card className="mt-8 space-y-4">
                        <div className="flex items-center gap-2 text-primary">
                            <Mail className="h-5 w-5" />
                            <span className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Lookup</span>
                        </div>
                        <div className="space-y-2">
                            <label className="text-sm text-muted-foreground">Hotel</label>
                            <select className="w-full rounded-xl border border-border bg-card px-3 py-2 text-foreground" value={hotelId} onChange={(e) => setHotelId(e.target.value)}>
                                <option value="">Select hotel</option>
                                {hotels.map((hotel) => (
                                    <option key={hotel.id} value={hotel.id}>{hotel.name}</option>
                                ))}
                            </select>
                        </div>
                        <Input label="Email" type="email" placeholder="you@example.com" autoComplete="email" value={guestEmail} onChange={(e) => setGuestEmail(e.target.value)} />
                        <Input label="Phone (optional)" type="tel" placeholder="+63 …" value={guestPhone} onChange={(e) => setGuestPhone(e.target.value)} />
                        <Button className="w-full" onClick={lookupBookings} disabled={loading}>
                            {loading ? 'Searching...' : 'Find reservations'}
                        </Button>
                    </Card>

                    <div className="mt-10 space-y-3">
                        {bookings.map((booking) => (
                            <Card key={booking.id} className="space-y-2">
                                <p className="font-semibold">{booking.booking_reference}</p>
                                <p className="text-sm text-muted-foreground">Room: {booking.room_id} • {booking.check_in_date} to {booking.check_out_date}</p>
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                                        <Calendar className="h-4 w-4" />
                                        {booking.status}
                                    </div>
                                    <button
                                        type="button"
                                        onClick={() => { window.location.href = `/api/bookings/${booking.booking_reference}/pdf`; }}
                                        className="rounded-full border border-primary px-3 py-1 text-xs text-primary"
                                    >
                                        Download PDF
                                    </button>
                                </div>
                            </Card>
                        ))}
                        {bookings.length === 0 && (
                            <div className="flex items-center justify-center gap-2 text-sm text-muted-foreground">
                                <Calendar className="h-4 w-4" />
                                No bookings found yet.
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </>
    );
}
