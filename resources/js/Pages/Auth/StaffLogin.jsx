import { Head, Link, usePage } from '@inertiajs/react';
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

    const errors = pageErrors && typeof pageErrors === 'object' ? pageErrors : {};
    const firstError = [...Object.values(errors).flat()][0];

    return (
        <AuthLayout title="MADYAW" subtitle="Staff Login">
            <Head title="Staff Login" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <motion.form
                method="post"
                action="/login"
                target="_self"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-4"
            >
                <input type="hidden" name="role" value="staff" />
                <input type="hidden" name="hotel_id" value={resolvedHotelId} />
                <input
                    className="w-full border border-border rounded-lg px-3 py-2"
                    name="username"
                    placeholder="Username"
                    autoComplete="username"
                    required
                    onChange={(e) => setForgotLinkUsername(e.target.value)}
                />
                <div className="relative">
                    <input
                        className="w-full border border-border rounded-lg px-3 py-2 pr-10"
                        name="password"
                        type={showPassword ? 'text' : 'password'}
                        placeholder="Password"
                        autoComplete="current-password"
                        required
                    />
                    <button type="button" onClick={() => setShowPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                        {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                </div>
                {firstError ? <p className="text-sm text-destructive">{String(firstError)}</p> : null}
                <Link href={`/auth/forgot-password?role=staff&username=${encodeURIComponent(forgotLinkUsername || '')}${resolvedHotelId ? `&hotel=${encodeURIComponent(resolvedHotelId)}` : ''}`} className="text-xs text-primary hover:underline">Forgot password?</Link>
                <button type="submit" className="w-full bg-primary text-primary-foreground rounded-full py-2.5">
                    Sign in
                </button>
            </motion.form>
        </AuthLayout>
    );
}
