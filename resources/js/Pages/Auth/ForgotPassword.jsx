import { Head, useForm } from '@inertiajs/react';
import { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import AuthLayout from '../../Layouts/AuthLayout';
import BackButton from '../../Components/BackButton';

export default function ForgotPassword({ prefill = {} }) {
    const [showNewPassword, setShowNewPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);
    const sendForm = useForm({
        role: prefill.role || 'admin',
        username: prefill.username || '',
    });
    const resetForm = useForm({
        code: '',
        new_password: '',
        new_password_confirmation: '',
    });

    return (
        <AuthLayout title="MADYAW" subtitle="Forgot Password">
            <Head title="Forgot Password" />
            <div className="mb-4">
                <BackButton fallback="/auth/select" />
            </div>
            <form
                onSubmit={(event) => {
                    event.preventDefault();
                    sendForm.post('/auth/forgot-password/send');
                }}
                className="space-y-3 mb-6"
            >
                <p className="text-sm text-muted-foreground">Step 1: send verification code to the hotel number tied to this username.</p>
                <select value={sendForm.data.role} onChange={(event) => sendForm.setData('role', event.target.value)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm">
                    <option value="admin">Admin</option>
                    <option value="staff">Staff</option>
                </select>
                <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="Username" value={sendForm.data.username} onChange={(event) => sendForm.setData('username', event.target.value)} />
                {sendForm.errors.username && <p className="text-sm text-destructive">{sendForm.errors.username}</p>}
                <button disabled={sendForm.processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">{sendForm.processing ? 'Sending...' : 'Send SMS Code'}</button>
            </form>

            <form
                onSubmit={(event) => {
                    event.preventDefault();
                    resetForm.post('/auth/forgot-password/reset');
                }}
                className="space-y-3"
            >
                <p className="text-sm text-muted-foreground">Step 2: verify code and set new password.</p>
                <input className="w-full border border-border rounded-lg px-3 py-2" placeholder="6-digit code" value={resetForm.data.code} onChange={(event) => resetForm.setData('code', event.target.value)} />
                <div className="relative">
                    <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showNewPassword ? 'text' : 'password'} placeholder="New password" value={resetForm.data.new_password} onChange={(event) => resetForm.setData('new_password', event.target.value)} />
                    <button type="button" onClick={() => setShowNewPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                        {showNewPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                </div>
                <div className="relative">
                    <input className="w-full border border-border rounded-lg px-3 py-2 pr-10" type={showConfirmPassword ? 'text' : 'password'} placeholder="Confirm new password" value={resetForm.data.new_password_confirmation} onChange={(event) => resetForm.setData('new_password_confirmation', event.target.value)} />
                    <button type="button" onClick={() => setShowConfirmPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                        {showConfirmPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                </div>
                {(resetForm.errors.code || resetForm.errors.new_password) && <p className="text-sm text-destructive">{resetForm.errors.code ?? resetForm.errors.new_password}</p>}
                <button disabled={resetForm.processing} className="w-full bg-primary text-primary-foreground rounded-full py-2.5">{resetForm.processing ? 'Updating...' : 'Reset Password'}</button>
            </form>
        </AuthLayout>
    );
}

