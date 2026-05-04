import { Head, Link, useForm, usePage } from '@inertiajs/react';
import { motion } from 'motion/react';
import { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import BackButton from '../../Components/BackButton';
import AuthLayout from '../../Layouts/AuthLayout';

export default function StaffLogin() {
    const [showPassword, setShowPassword] = useState(false);
    const [forgotLinkUsername, setForgotLinkUsername] = useState('');
    const { activeHotelId: activeHotelIdProp = '', errors: pageErrors = {} } = usePage().props;
    const hotelFromUrl = typeof window !== 'undefined'
        ? (new URLSearchParams(window.location.search).get('hotel') ?? '')
        : '';
    const resolvedHotelId = (typeof activeHotelIdProp === 'string' && activeHotelIdProp !== '')
        ? activeHotelIdProp
        : hotelFromUrl;

    const form = useForm({
        username: '',
        password: '',
    });

    const errors = pageErrors && typeof pageErrors === 'object' ? pageErrors : {};
    const firstError = form.errors.username
        || form.errors.password
        || form.errors.email
        || [...Object.values(errors).flat()][0];

    function submit(e) {
        e.preventDefault();
        form.transform((data) => ({
            role: 'staff',
            hotel_id: resolvedHotelId,
            username: data.username,
            password: data.password,
        }));
        form.post('/login');
    }

    return (
        <AuthLayout title="MADYAW" subtitle="Staff Login">
            <Head title="Staff Login" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <motion.form
                onSubmit={submit}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-4"
            >
                <input
                    className="w-full border border-border rounded-lg px-3 py-2"
                    name="username"
                    placeholder="Username"
                    autoComplete="username"
                    required
                    value={form.data.username}
                    onChange={(e) => {
                        form.setData('username', e.target.value);
                        setForgotLinkUsername(e.target.value);
                    }}
                />
                <div className="relative">
                    <input
                        className="w-full border border-border rounded-lg px-3 py-2 pr-10"
                        name="password"
                        type={showPassword ? 'text' : 'password'}
                        placeholder="Password"
                        autoComplete="current-password"
                        required
                        value={form.data.password}
                        onChange={(e) => form.setData('password', e.target.value)}
                    />
                    <button type="button" onClick={() => setShowPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                        {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                </div>
                {firstError ? <p className="text-sm text-destructive">{String(firstError)}</p> : null}
                <Link href={`/auth/forgot-password?role=staff&username=${encodeURIComponent(forgotLinkUsername || '')}${resolvedHotelId ? `&hotel=${encodeURIComponent(resolvedHotelId)}` : ''}`} className="text-xs text-primary hover:underline">Forgot password?</Link>
                <button type="submit" disabled={form.processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5 disabled:opacity-60">
                    Sign in
                </button>
            </motion.form>
        </AuthLayout>
    );
}
