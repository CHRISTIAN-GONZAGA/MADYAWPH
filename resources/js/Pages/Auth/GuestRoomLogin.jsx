import { Head, usePage } from '@inertiajs/react';
import { motion } from 'motion/react';
import BackButton from '../../Components/BackButton';
import AuthLayout from '../../Layouts/AuthLayout';

export default function GuestRoomLogin() {
    const { activeHotelId: activeHotelIdProp = '', errors: pageErrors = {} } = usePage().props;
    const hotelFromUrl = typeof window !== 'undefined'
        ? (new URLSearchParams(window.location.search).get('hotel') ?? '')
        : '';
    const resolvedHotelId = (typeof activeHotelIdProp === 'string' && activeHotelIdProp !== '')
        ? activeHotelIdProp
        : hotelFromUrl;

    const errors = pageErrors && typeof pageErrors === 'object' ? pageErrors : {};
    const firstError = [...Object.values(errors).flat()][0];

    return (
        <AuthLayout title="MADYAW" subtitle="Guest In-House Access">
            <Head title="Guest Login" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <motion.form
                method="post"
                action="/auth/guest/login"
                target="_self"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-4"
            >
                <input type="hidden" name="hotel_id" value={resolvedHotelId} />
                <input className="w-full border border-border rounded-lg px-3 py-2" name="room" placeholder="Room Number" autoComplete="off" required />
                <input className="w-full border border-border rounded-lg px-3 py-2" name="password" type="password" placeholder="Room Password" autoComplete="off" required />
                {firstError ? <p className="text-sm text-destructive">{String(firstError)}</p> : null}
                <button type="submit" className="w-full bg-primary text-primary-foreground rounded-full py-2.5">
                    Access Room Portal
                </button>
            </motion.form>
        </AuthLayout>
    );
}
