import { Link } from '@inertiajs/react';
import { BarChart3, Building2, Crown, ShieldAlert, Sparkles } from 'lucide-react';
import { useState } from 'react';
import AppLayout from '../Layouts/AppLayout';
import Button from '../Components/Button';
import Card from '../Components/Card';
import StatCard from '../Components/StatCard';

const navTabs = ['Overview', 'Guest chat', 'SOS alerts', 'Staff', 'Sales', 'Tasks', 'Logs'];

export default function AdminDashboard() {
    const [tab, setTab] = useState('Overview');

    return (
        <AppLayout title="Administrator dashboard" subtitle="Balanghai Hotel">
            <div className="mb-6 flex flex-wrap gap-2">
                <Button variant="secondary" className="gap-2 py-2 text-sm" onClick={() => { window.location.href = '/api/reports/sales-pdf'; }}>
                    <Crown className="h-4 w-4" />
                    Sales PDF
                </Button>
                <Link
                    href="/rooms"
                    className="inline-flex min-h-11 items-center justify-center gap-2 rounded-full border border-primary bg-transparent px-5 py-2 text-sm font-medium text-primary transition hover:bg-card"
                >
                    <Building2 className="h-4 w-4" />
                    Rooms
                </Link>
            </div>

            <div className="-mx-4 mb-8 flex gap-2 overflow-x-auto px-4 pb-2 sm:mx-0 sm:flex-wrap sm:overflow-visible sm:px-0">
                {navTabs.map((label) => (
                    <button
                        key={label}
                        type="button"
                        onClick={() => setTab(label)}
                        className={`min-h-[44px] shrink-0 rounded-full border px-4 py-2 text-sm font-medium transition ${
                            tab === label
                                ? 'border-primary bg-primary text-primary-foreground shadow-card'
                                : 'border-border bg-card text-muted-foreground hover:border-primary/40'
                        }`}
                    >
                        {label}
                    </button>
                ))}
            </div>

            <section className="mb-8">
                <h2 className="mb-4 font-serif text-lg font-semibold text-foreground">Key metrics</h2>
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <StatCard label="Rooms occupied" value="8/12" trend="+2 vs last week" accent="green" />
                    <StatCard label="Revenue (period)" value="₱95,000" accent="primary" />
                    <StatCard label="Bookings" value="40" accent="amber" />
                    <StatCard label="Pending tasks" value="6" accent="red" />
                </div>
            </section>

            <div className="grid gap-6 lg:grid-cols-2">
                <Card>
                    <div className="mb-4 flex items-center gap-2">
                        <Sparkles className="h-5 w-5 text-accent" />
                        <h3 className="font-serif text-xl font-semibold">Room management</h3>
                    </div>
                    <p className="text-sm text-muted-foreground">Category view, availability, and pricing connect to your API.</p>
                    <Link
                        href="/rooms"
                        className="mt-4 inline-flex min-h-11 items-center justify-center rounded-full border border-primary px-6 py-3 text-base font-medium text-primary transition hover:bg-card"
                    >
                        Open category view
                    </Link>
                </Card>

                <Card>
                    <div className="mb-4 flex items-center gap-2">
                        <GiftIcon />
                        <h3 className="font-serif text-xl font-semibold">Amenity requests</h3>
                    </div>
                    <p className="mb-3 text-sm text-muted-foreground">5 pending requests</p>
                    <div className="space-y-3">
                        <div className="rounded-xl border border-border bg-background p-4">
                            <p className="font-medium">Continental breakfast ×2</p>
                            <p className="text-xs text-muted-foreground">Room 102 · Alice Brown · Apr 13, 7:30 AM</p>
                            <Button className="mt-3 w-full py-2 text-sm">Mark fulfilled</Button>
                        </div>
                    </div>
                </Card>
            </div>

            <Card className="mt-6">
                <div className="mb-4 flex flex-wrap items-center justify-between gap-4">
                    <div className="flex items-center gap-2">
                        <BarChart3 className="h-5 w-5 text-primary" />
                        <h3 className="font-serif text-xl font-semibold">Sales performance</h3>
                    </div>
                    <div className="flex gap-2">
                        {['Weekly', 'Monthly'].map((p) => (
                            <span
                                key={p}
                                className={`rounded-full px-3 py-1 text-xs font-semibold ${p === 'Weekly' ? 'bg-primary text-primary-foreground' : 'border border-border text-muted-foreground'}`}
                            >
                                {p}
                            </span>
                        ))}
                        <Button variant="secondary" className="py-1 text-xs" onClick={() => { window.location.href = '/api/reports/sales-csv'; }}>
                            Export
                        </Button>
                    </div>
                </div>
                <div className="flex h-40 items-end justify-between gap-2 rounded-xl bg-gradient-to-t from-border/50 to-transparent px-4 pb-2 pt-8">
                    {[40, 55, 70, 45, 60, 75, 50].map((h, i) => (
                        <div key={i} className="flex flex-1 flex-col items-center gap-1">
                            <div className="w-full rounded-t-md bg-primary/80" style={{ height: `${h}%` }} />
                            <span className="text-[10px] text-muted-foreground">{['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]}</span>
                        </div>
                    ))}
                </div>
                <p className="mt-4 font-serif text-2xl font-bold text-foreground">Total revenue: ₱95,000</p>
            </Card>

            <Card className="mt-6 border-destructive/20 bg-destructive/5">
                <div className="flex items-center gap-2 text-destructive">
                    <ShieldAlert className="h-6 w-6" />
                    <h3 className="font-serif text-lg font-semibold">SOS alerts</h3>
                </div>
                <p className="mt-2 text-sm text-muted-foreground">2 pending — staff routing via your notification channels.</p>
            </Card>
        </AppLayout>
    );
}

function GiftIcon() {
    return (
        <span className="flex h-8 w-8 items-center justify-center rounded-full bg-accent/20 text-lg" aria-hidden>
            🎁
        </span>
    );
}
