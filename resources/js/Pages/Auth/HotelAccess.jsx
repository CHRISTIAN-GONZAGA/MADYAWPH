import { Head, useForm } from '@inertiajs/react';
import { useState } from 'react';
import { motion } from 'motion/react';
import { Eye, EyeOff } from 'lucide-react';
import AuthLayout from '../../Layouts/AuthLayout';

export default function HotelAccess() {
    const [mode, setMode] = useState('signin');
    const [showSignInPassword, setShowSignInPassword] = useState(false);
    const [showSignUpPassword, setShowSignUpPassword] = useState(false);
    const [showSignUpConfirmPassword, setShowSignUpConfirmPassword] = useState(false);
    const signInForm = useForm({
        username: '',
        password: '',
    });
    const signUpForm = useForm({
        username: '',
        password: '',
        password_confirmation: '',
        hotel_name: '',
        location: '',
        contact_number: '',
        admin_email: '',
    });

    async function ensureCsrfCookie() {
        await window.axios.get('/sanctum/csrf-cookie');
    }

    async function submitSignIn(event) {
        event.preventDefault();
        await ensureCsrfCookie();
        signInForm.post('/auth/hotel/login');
    }

    async function submitSignUp(event) {
        event.preventDefault();
        await ensureCsrfCookie();
        signUpForm.post('/auth/hotel/register');
    }

    const errors = mode === 'signin' ? signInForm.errors : signUpForm.errors;

    return (
        <AuthLayout title="MADYAW" subtitle="Hotel Access">
            <Head title="Hotel Access" />
            <div className="mb-4 flex gap-2 rounded-xl border border-border bg-card p-1">
                <button type="button" onClick={() => setMode('signin')} className={`flex-1 rounded-lg py-2 text-sm ${mode === 'signin' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground'}`}>Sign In</button>
                <button type="button" onClick={() => setMode('signup')} className={`flex-1 rounded-lg py-2 text-sm ${mode === 'signup' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground'}`}>Register Hotel</button>
            </div>

            {mode === 'signin' ? (
                <motion.form method="post" target="_self" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} onSubmit={submitSignIn} className="space-y-4">
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Hotel Username" value={signInForm.data.username} onChange={(event) => signInForm.setData('username', event.target.value)} required />
                    <div className="relative">
                        <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showSignInPassword ? 'text' : 'password'} placeholder="Password" value={signInForm.data.password} onChange={(event) => signInForm.setData('password', event.target.value)} required />
                        <button type="button" onClick={() => setShowSignInPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                            {showSignInPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                    </div>
                    {Object.keys(errors).length > 0 && <p className="text-sm text-destructive">{Object.values(errors)[0]}</p>}
                    <a href={`/auth/forgot-password?role=admin&username=${encodeURIComponent(signInForm.data.username || '')}`} className="text-xs text-primary hover:underline">Forgot password?</a>
                    <button type="submit" disabled={signInForm.processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">{signInForm.processing ? 'Signing in...' : 'Continue'}</button>
                </motion.form>
            ) : (
                <motion.form method="post" target="_self" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} onSubmit={submitSignUp} className="space-y-3">
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Hotel Username" value={signUpForm.data.username} onChange={(event) => signUpForm.setData('username', event.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Admin Email" type="email" value={signUpForm.data.admin_email} onChange={(event) => signUpForm.setData('admin_email', event.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Hotel Name" value={signUpForm.data.hotel_name} onChange={(event) => signUpForm.setData('hotel_name', event.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Hotel Location" value={signUpForm.data.location} onChange={(event) => signUpForm.setData('location', event.target.value)} required />
                    <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Mobile / Tel Number" value={signUpForm.data.contact_number} onChange={(event) => signUpForm.setData('contact_number', event.target.value)} required />
                    <div className="relative">
                        <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showSignUpPassword ? 'text' : 'password'} placeholder="Password" value={signUpForm.data.password} onChange={(event) => signUpForm.setData('password', event.target.value)} required />
                        <button type="button" onClick={() => setShowSignUpPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                            {showSignUpPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                    </div>
                    <div className="relative">
                        <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showSignUpConfirmPassword ? 'text' : 'password'} placeholder="Confirm Password" value={signUpForm.data.password_confirmation} onChange={(event) => signUpForm.setData('password_confirmation', event.target.value)} required />
                        <button type="button" onClick={() => setShowSignUpConfirmPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                            {showSignUpConfirmPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                    </div>
                    {Object.keys(errors).length > 0 && <p className="text-sm text-destructive">{Object.values(errors)[0]}</p>}
                    <button type="submit" disabled={signUpForm.processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">{signUpForm.processing ? 'Registering...' : 'Create Hotel Account'}</button>
                </motion.form>
            )}
        </AuthLayout>
    );
}
