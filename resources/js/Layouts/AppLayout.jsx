import { router } from '@inertiajs/react';
import { Building2, LogOut } from 'lucide-react';
import BackButton from '../Components/BackButton';
import Button from '../Components/Button';

export default function AppLayout({ title, subtitle, children, showLogout = true }) {
    const logout = () => router.post('/logout');

    return (
        <div className="min-h-screen bg-linen animate-fade-up">
            <header className="sticky top-0 z-40 border-b border-border/80 bg-card/90 shadow-sm backdrop-blur-md">
                <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-4 py-4 sm:px-6">
                    <div className="flex items-center gap-3">
                        <BackButton fallback="/login" />
                        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-card animate-pulse-glow">
                            <Building2 className="h-6 w-6" strokeWidth={1.75} />
                        </div>
                        <div>
                            <h1 className="font-serif text-xl font-bold tracking-tight text-foreground sm:text-2xl">{title}</h1>
                            {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
                        </div>
                    </div>
                    {showLogout && (
                        <Button type="button" variant="secondary" className="gap-2 px-4 py-2 text-sm" onClick={logout}>
                            <LogOut className="h-4 w-4" />
                            Logout
                        </Button>
                    )}
                </div>
            </header>
            <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6 animate-fade-up">{children}</main>
        </div>
    );
}
