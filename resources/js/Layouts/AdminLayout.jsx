import { useEffect, useState } from 'react';
import { Link, router } from '@inertiajs/react';
import axios from 'axios';
import { CreditCard, LogOut, Palette, RotateCcw, X } from 'lucide-react';
import { applyThemeColor } from '../Utils/theme';

const DEFAULT_THEME = '#2563eb';

export default function AdminLayout({ user, children, credits = null, theme = null }) {
    const [showCreditsModal, setShowCreditsModal] = useState(false);
    const [showLogoutModal, setShowLogoutModal] = useState(false);
    const [showThemePanel, setShowThemePanel] = useState(false);
    const [depositAmount, setDepositAmount] = useState('');
    const [depositMethod, setDepositMethod] = useState('gcash');
    const [scope, setScope] = useState('user');
    const initialColor = theme?.userThemeColor ?? theme?.hotelThemeColor ?? DEFAULT_THEME;
    const [themeColor, setThemeColor] = useState(initialColor);

    useEffect(() => {
        applyThemeColor(initialColor);
    }, [initialColor]);

    const balance = credits?.currentCredits ?? 0;

    async function rechargeCredits() {
        const amount = Number(depositAmount);
        if (!Number.isFinite(amount) || amount <= 0) {
            alert('Enter a valid deposit amount.');
            return;
        }
        const { data } = await axios.post('/admin/credits/recharge', { amount, method: depositMethod });
        if (data?.redirect_url) {
            window.location.href = data.redirect_url;
            return;
        }
        setShowCreditsModal(false);
        setDepositAmount('');
        router.reload({ only: ['credits'] });
    }

    async function persistTheme(nextColor) {
        await axios.post('/admin/theme', { theme_color: nextColor, scope });
        router.reload({ only: ['theme'] });
    }

    async function resetTheme() {
        await axios.delete('/admin/theme/reset');
        setThemeColor(theme?.hotelThemeColor ?? DEFAULT_THEME);
        applyThemeColor(theme?.hotelThemeColor ?? DEFAULT_THEME);
        router.reload({ only: ['theme'] });
    }

    return (
        <div className="min-h-screen bg-background text-foreground">
            <header className="sticky top-0 z-30 bg-card/95 backdrop-blur border-b border-border">
                <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between gap-3">
                    <div>
                        <p className="font-serif text-xl">MADYAW Admin</p>
                        <p className="text-xs text-muted-foreground">{user?.hotelName ?? 'Hotel Management'}</p>
                    </div>
                    <nav className="flex items-center gap-2 sm:gap-4 text-sm overflow-x-auto">
                        <Link href="/admin/dashboard" className="hover:text-primary">Dashboard</Link>
                        <button type="button" onClick={() => setShowCreditsModal(true)} className="hover:text-primary inline-flex items-center gap-1"><CreditCard className="w-4 h-4" /> Credits</button>
                        <button type="button" onClick={() => setShowThemePanel((prev) => !prev)} className="hover:text-primary inline-flex items-center gap-1"><Palette className="w-4 h-4" /> Theme</button>
                        <button type="button" onClick={() => setShowLogoutModal(true)} className="text-red-600 inline-flex items-center gap-1"><LogOut className="w-4 h-4" /> Logout</button>
                    </nav>
                </div>
            </header>
            <main className="max-w-7xl mx-auto px-4 py-6">{children}</main>

            {showCreditsModal && (
                <div className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center" onClick={() => setShowCreditsModal(false)}>
                    <div className="w-full max-w-md rounded-2xl border border-border bg-card p-5 space-y-3" onClick={(event) => event.stopPropagation()}>
                        <div className="flex items-center justify-between">
                            <h3 className="font-serif text-xl">Credits</h3>
                            <button type="button" onClick={() => setShowCreditsModal(false)}><X className="w-4 h-4" /></button>
                        </div>
                        <p className="text-sm text-muted-foreground">Current balance: <span className="font-semibold text-foreground">PHP {Number(balance).toLocaleString()}</span></p>
                        <select value={depositMethod} onChange={(event) => setDepositMethod(event.target.value)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm">
                            <option value="gcash">GCash (PayMongo)</option>
                            <option value="paymaya">PayMaya (PayMongo)</option>
                        </select>
                        <input value={depositAmount} onChange={(event) => setDepositAmount(event.target.value)} type="number" min="1" className="w-full border border-border rounded-lg px-3 py-2 bg-background" placeholder="Custom deposit amount" />
                        <button type="button" onClick={rechargeCredits} className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground">Recharge</button>
                    </div>
                </div>
            )}

            {showLogoutModal && (
                <div className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center" onClick={() => setShowLogoutModal(false)}>
                    <div className="w-full max-w-sm rounded-2xl border border-border bg-card p-5 space-y-3" onClick={(event) => event.stopPropagation()}>
                        <h3 className="font-serif text-xl">Confirm Logout</h3>
                        <p className="text-sm text-muted-foreground">Are you sure you want to logout?</p>
                        <div className="flex gap-2 justify-end">
                            <button type="button" onClick={() => setShowLogoutModal(false)} className="px-3 py-2 rounded-lg border border-border">Cancel</button>
                            <Link href="/logout" method="post" as="button" className="px-3 py-2 rounded-lg bg-red-600 text-white">Logout</Link>
                        </div>
                    </div>
                </div>
            )}

            {showThemePanel && (
                <div className="fixed right-4 top-20 z-40 w-80 rounded-2xl border border-border bg-card p-4 space-y-3 shadow-lg">
                    <div className="flex items-center justify-between">
                        <h3 className="font-serif text-lg">Customize Theme</h3>
                        <button type="button" onClick={() => setShowThemePanel(false)}><X className="w-4 h-4" /></button>
                    </div>
                    <input
                        type="color"
                        value={themeColor}
                        onChange={(event) => {
                            const nextColor = event.target.value;
                            setThemeColor(nextColor);
                            applyThemeColor(nextColor);
                        }}
                        className="h-12 w-full rounded-lg border border-border bg-background"
                    />
                    <select value={scope} onChange={(event) => setScope(event.target.value)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm">
                        <option value="user">Apply to my account</option>
                        <option value="hotel">Apply hotel-wide</option>
                    </select>
                    <div className="flex gap-2">
                        <button type="button" onClick={() => persistTheme(themeColor)} className="flex-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Save Theme</button>
                        <button type="button" onClick={resetTheme} className="px-3 py-2 rounded-lg border border-border text-sm inline-flex items-center gap-1"><RotateCcw className="w-4 h-4" /> Reset</button>
                    </div>
                </div>
            )}
        </div>
    );
}
