import { Head, useForm } from '@inertiajs/react';
import { motion } from 'motion/react';
import { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import BackButton from '../../Components/BackButton';
import AuthLayout from '../../Layouts/AuthLayout';

export default function StaffLogin() {
    const [showPassword, setShowPassword] = useState(false);
    const hotelId = typeof window !== 'undefined'
        ? (new URLSearchParams(window.location.search).get('hotel') ?? '')
        : '';
    const { data, setData, post, processing, errors } = useForm({
        username: '',
        password: '',
        role: 'staff',
        hotel_id: hotelId,
    });

    async function ensureCsrfCookie() {
        await window.axios.get('/sanctum/csrf-cookie');
    }

    async function submit(e) {
        e.preventDefault();
        await ensureCsrfCookie();
        post('/login');
    }

    return (
        <AuthLayout title="MADYAW" subtitle="Staff Login">
            <Head title="Staff Login" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <motion.form initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} onSubmit={submit} className="space-y-4">
                <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Username" value={data.username} onChange={(e) => setData('username', e.target.value)} />
                <input type="hidden" value={data.hotel_id} readOnly />
                <div className="relative">
                    <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showPassword ? 'text' : 'password'} placeholder="Password" value={data.password} onChange={(e) => setData('password', e.target.value)} />
                    <button type="button" onClick={() => setShowPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                        {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                </div>
                {Object.keys(errors).length > 0 && <p className="text-sm text-destructive">{Object.values(errors)[0]}</p>}
                <a href={`/auth/forgot-password?role=staff&username=${encodeURIComponent(data.username || '')}${data.hotel_id ? `&hotel=${encodeURIComponent(data.hotel_id)}` : ''}`} className="text-xs text-primary hover:underline">Forgot password?</a>
                <button disabled={processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">
                    {processing ? 'Signing in...' : 'Sign in'}
                </button>
            </motion.form>
        </AuthLayout>
    );
}
