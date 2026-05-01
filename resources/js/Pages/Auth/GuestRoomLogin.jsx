import { Head, useForm } from '@inertiajs/react';
import { motion } from 'motion/react';
import BackButton from '../../Components/BackButton';
import AuthLayout from '../../Layouts/AuthLayout';

export default function GuestRoomLogin() {
    const hotelId = typeof window !== 'undefined'
        ? (new URLSearchParams(window.location.search).get('hotel') ?? '')
        : '';
    const { data, setData, post, processing, errors } = useForm({
        room: '',
        password: '',
        hotel_id: hotelId,
    });

    function submit(e) {
        e.preventDefault();
        post('/auth/guest/login');
    }

    return (
        <AuthLayout title="MADYAW" subtitle="Guest In-House Access">
            <Head title="Guest Login" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <motion.form initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} onSubmit={submit} className="space-y-4">
                <input type="hidden" value={data.hotel_id} readOnly />
                <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Room Number" value={data.room} onChange={(e) => setData('room', e.target.value)} />
                <input className="w-full border border-border rounded-lg px-3 py-2" type="password" placeholder="Room Password" value={data.password} onChange={(e) => setData('password', e.target.value)} />
                {(errors.room || errors.password) && (
                    <p className="text-sm text-destructive">{errors.room ?? errors.password}</p>
                )}
                <button disabled={processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">
                    {processing ? 'Entering...' : 'Access Room Portal'}
                </button>
            </motion.form>
        </AuthLayout>
    );
}
