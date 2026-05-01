import { Link } from '@inertiajs/react';
import { useState } from 'react';
import { Palette, RotateCcw, X } from 'lucide-react';
import { applyThemeColor } from '../utils/theme';

export default function GuestLayout({ user, roomInfo, children }) {
    const [showTheme, setShowTheme] = useState(false);
    const [themeColor, setThemeColor] = useState(localStorage.getItem('app_theme_color') || '#2563eb');

    return (
        <div className="min-h-screen bg-background text-foreground">
            <header className="bg-card border-b border-border">
                <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between gap-3">
                    <div>
                        <h1 className="font-serif text-xl">Guest Dashboard</h1>
                        <p className="text-xs text-muted-foreground">
                            {user?.name ?? 'Guest'} {roomInfo?.roomNumber ? `• Room ${roomInfo.roomNumber}` : ''}
                        </p>
                    </div>
                    <div className="flex items-center gap-3">
                        <button type="button" onClick={() => setShowTheme((prev) => !prev)} className="text-sm hover:text-primary inline-flex items-center gap-1"><Palette className="w-4 h-4" /> Theme</button>
                        <Link href="/logout" method="post" as="button" className="text-sm hover:text-primary">Logout</Link>
                    </div>
                </div>
            </header>
            <main className="max-w-7xl mx-auto px-4 py-6">{children}</main>
            {showTheme && (
                <div className="fixed right-4 top-20 z-40 w-72 rounded-2xl border border-border bg-card p-4 space-y-3 shadow-lg">
                    <div className="flex items-center justify-between">
                        <h3 className="font-serif text-lg">Theme</h3>
                        <button type="button" onClick={() => setShowTheme(false)}><X className="w-4 h-4" /></button>
                    </div>
                    <input
                        type="color"
                        value={themeColor}
                        onChange={(event) => {
                            const next = event.target.value;
                            setThemeColor(next);
                            applyThemeColor(next);
                        }}
                        className="h-11 w-full rounded-lg border border-border bg-background"
                    />
                    <button
                        type="button"
                        className="w-full px-3 py-2 rounded-lg border border-border text-sm inline-flex items-center justify-center gap-1"
                        onClick={() => {
                            applyThemeColor('#2563eb');
                            setThemeColor('#2563eb');
                        }}
                    >
                        <RotateCcw className="w-4 h-4" /> Reset
                    </button>
                </div>
            )}
        </div>
    );
}
