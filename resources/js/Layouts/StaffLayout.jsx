import { Link } from '@inertiajs/react';
import { useState } from 'react';
import axios from 'axios';
import { Palette, RotateCcw, X } from 'lucide-react';
import { applyThemeColor } from '../utils/theme';

const DEFAULT_THEME = '#2563eb';

export default function StaffLayout({ user, children }) {
    const [showTheme, setShowTheme] = useState(false);
    const [themeColor, setThemeColor] = useState(localStorage.getItem('app_theme_color') || DEFAULT_THEME);

    return (
        <div className="min-h-screen bg-background text-foreground">
            <header className="bg-card border-b border-border">
                <div className="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
                    <h1 className="font-serif text-xl">MADYAW Staff Portal</h1>
                    <div className="flex gap-3 items-center text-sm">
                        <span className="text-muted-foreground">{user?.name ?? 'Staff'}</span>
                        <button type="button" onClick={() => setShowTheme((prev) => !prev)} className="hover:text-primary inline-flex items-center gap-1"><Palette className="w-4 h-4" /> Theme</button>
                        <Link href="/logout" method="post" as="button" className="hover:text-primary">Logout</Link>
                    </div>
                </div>
            </header>
            <main className="max-w-6xl mx-auto px-4 py-6">{children}</main>
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
                    <div className="flex gap-2">
                        <button
                            type="button"
                            className="flex-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm"
                            onClick={async () => {
                                await axios.put('/api/theme', { theme_color: themeColor, scope: 'user' });
                            }}
                        >
                            Save
                        </button>
                        <button
                            type="button"
                            className="px-3 py-2 rounded-lg border border-border text-sm inline-flex items-center gap-1"
                            onClick={async () => {
                                await axios.delete('/api/theme/reset');
                                applyThemeColor(DEFAULT_THEME);
                                setThemeColor(DEFAULT_THEME);
                            }}
                        >
                            <RotateCcw className="w-4 h-4" /> Reset
                        </button>
                    </div>
                </div>
            )}
        </div>
    );
}
