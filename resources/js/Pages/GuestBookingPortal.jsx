import { Head, useForm } from '@inertiajs/react';
import axios from 'axios';
import { CalendarDays, Hotel, User } from 'lucide-react';
import { useState } from 'react';
import BackButton from '../Components/BackButton';
import Button from '../Components/Button';
import Card from '../Components/Card';
import Input from '../Components/Input';

const paymentOptions = ['Cash', 'GCash', 'PayMaya', 'Credit Card'];

export default function GuestBookingPortal({ hotelId = '', hotelName = '', roomId = '', roomNumber = '' }) {
    const [submitError, setSubmitError] = useState('');
    const [successMessage, setSuccessMessage] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const { data, setData } = useForm({
        guest_name: '',
        guest_email: '',
        guest_phone: '',
        check_in_date: '',
        check_out_date: '',
        payment_method: paymentOptions[0],
    });

    const submitBooking = async (e) => {
        e.preventDefault();
        setSubmitError('');
        setSuccessMessage('');

        if (!hotelId || !roomId) {
            setSubmitError('Missing hotel or room selection. Please restart the kiosk flow.');
            return;
        }

        setIsSubmitting(true);
        try {
            const response = await axios.post('/api/bookings', {
                ...data,
                room_id: roomId,
                hotel_id: hotelId,
                source: 'kiosk',
            });
            setSuccessMessage(`Booking confirmed. Reference: ${response?.data?.booking_reference ?? 'N/A'}`);
        } catch (error) {
            setSubmitError(error?.response?.data?.message || 'Could not complete booking. Please review the details.');
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <>
            <Head title="Book a stay" />
            <div className="min-h-screen bg-linen px-4 py-8">
                <div className="mx-auto max-w-lg">
                    <BackButton fallback="/kiosk" />
                    <h1 className="font-serif text-3xl font-bold text-foreground">Confirm your booking</h1>
                    <p className="mt-2 text-muted-foreground">Complete guest details to reserve this room.</p>

                    <Card className="mt-6 space-y-3">
                        <div className="flex items-center gap-2 text-sm text-muted-foreground">
                            <Hotel className="h-4 w-4 text-primary" />
                            Hotel
                        </div>
                        <p className="font-medium text-foreground">{hotelName || 'Selected hotel'}</p>
                        <div className="flex items-center gap-2 text-sm text-muted-foreground">
                            <CalendarDays className="h-4 w-4 text-primary" />
                            Room {roomNumber || 'N/A'}
                        </div>
                    </Card>

                    <form className="mt-6 space-y-4" onSubmit={submitBooking}>
                        <Input
                            label="Guest name"
                            value={data.guest_name}
                            onChange={(e) => setData('guest_name', e.target.value)}
                            placeholder="Juan Dela Cruz"
                        />
                        <Input
                            label="Email"
                            type="email"
                            value={data.guest_email}
                            onChange={(e) => setData('guest_email', e.target.value)}
                            placeholder="guest@email.com"
                        />
                        <Input
                            label="Phone"
                            value={data.guest_phone}
                            onChange={(e) => setData('guest_phone', e.target.value)}
                            placeholder="+63 9xx xxx xxxx"
                        />

                        <div className="grid gap-4 sm:grid-cols-2">
                            <Input
                                label="Check-in date"
                                type="date"
                                value={data.check_in_date}
                                onChange={(e) => setData('check_in_date', e.target.value)}
                            />
                            <Input
                                label="Check-out date"
                                type="date"
                                value={data.check_out_date}
                                onChange={(e) => setData('check_out_date', e.target.value)}
                            />
                        </div>

                        <div>
                            <label className="mb-1 block text-sm font-medium text-foreground">Payment method</label>
                            <select
                                value={data.payment_method}
                                onChange={(e) => setData('payment_method', e.target.value)}
                                className="w-full rounded-xl border border-border bg-card px-4 py-3 text-sm"
                            >
                                {paymentOptions.map((option) => (
                                    <option key={option} value={option}>
                                        {option}
                                    </option>
                                ))}
                            </select>
                        </div>

                        {submitError && (
                            <p className="rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">{submitError}</p>
                        )}
                        {successMessage && (
                            <p className="rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">{successMessage}</p>
                        )}

                        <Button type="submit" className="w-full" disabled={isSubmitting}>
                            <User className="mr-2 h-4 w-4" />
                            {isSubmitting ? 'Booking...' : 'Confirm booking'}
                        </Button>
                    </form>
                </div>
            </div>
        </>
    );
}
