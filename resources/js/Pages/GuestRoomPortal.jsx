import { Head } from '@inertiajs/react';
import { AlertTriangle, DoorOpen, Gift, Minus, Plus, ShoppingCart } from 'lucide-react';
import { useState } from 'react';
import Badge from '../Components/Badge';
import BackButton from '../Components/BackButton';
import Button from '../Components/Button';
import Card from '../Components/Card';

const tabs = [
    { id: 'services', label: 'In-room services' },
    { id: 'amenities', label: 'Free items' },
    { id: 'chat', label: 'Concierge chat' },
];

const freeAmenities = [
    { emoji: '🍳', name: 'Continental breakfast', servings: 2 },
    { emoji: '💧', name: 'Bottled water', servings: 4 },
];

const services = [
    { title: 'Club sandwich', category: 'Food', price: '₱450', desc: 'Premium club sandwich with fries and salad' },
];

export default function GuestRoomPortal({ room = '102' }) {
    const [tab, setTab] = useState('services');
    const [cartOpen, setCartOpen] = useState(false);

    return (
        <>
            <Head title="Guest room" />
            <div className="min-h-screen bg-linen pb-24">
                <header className="sticky top-0 z-30 border-b border-border bg-card/95 shadow-sm backdrop-blur-md">
                    <div className="mx-auto flex max-w-lg flex-col gap-3 px-4 py-4">
                        <BackButton fallback="/login" />
                        <div className="flex items-center justify-between">
                            <div className="flex items-center gap-3">
                                <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
                                    <DoorOpen className="h-6 w-6" />
                                </div>
                                <div>
                                    <p className="font-serif text-lg font-semibold text-foreground">Welcome</p>
                                    <p className="text-sm text-muted-foreground">Room {room}</p>
                                </div>
                            </div>
                            <div className="flex gap-2">
                                <button
                                    type="button"
                                    onClick={() => setCartOpen(true)}
                                    className="flex h-11 w-11 items-center justify-center rounded-full border border-border bg-card shadow-card"
                                >
                                    <ShoppingCart className="h-5 w-5 text-primary" />
                                </button>
                                <button
                                    type="button"
                                    className="flex h-11 w-11 items-center justify-center rounded-full border border-destructive/30 bg-destructive/10 text-destructive"
                                    aria-label="Emergency"
                                >
                                    <AlertTriangle className="h-5 w-5" />
                                </button>
                            </div>
                        </div>
                        <p className="text-xs text-muted-foreground">In: Apr 15 · Out: Apr 18</p>
                        <div className="flex gap-1 overflow-x-auto rounded-full bg-background p-1">
                            {tabs.map((t) => (
                                <button
                                    key={t.id}
                                    type="button"
                                    onClick={() => setTab(t.id)}
                                    className={`min-h-[44px] flex-1 rounded-full px-3 py-2 text-sm font-medium transition ${
                                        tab === t.id ? 'bg-primary text-primary-foreground shadow-card' : 'text-muted-foreground hover:text-foreground'
                                    }`}
                                >
                                    {t.label}
                                </button>
                            ))}
                        </div>
                    </div>
                </header>

                <main className="mx-auto max-w-lg px-4 py-6">
                    {tab === 'services' && (
                        <div className="space-y-4">
                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">In-room services</p>
                            <div className="flex flex-wrap gap-2">
                                {['Food', 'Amenities', 'Room service'].map((c) => (
                                    <span
                                        key={c}
                                        className="rounded-full border border-primary bg-primary px-3 py-1.5 text-xs font-semibold text-primary-foreground"
                                    >
                                        {c}
                                    </span>
                                ))}
                            </div>
                            {services.map((s) => (
                                <Card key={s.title} interactive className="overflow-hidden p-0">
                                    <div className="h-40 bg-gradient-to-br from-border to-muted/40" />
                                    <div className="p-4">
                                        <Badge variant="neutral" className="mb-2">
                                            {s.category}
                                        </Badge>
                                        <h3 className="font-serif text-xl font-semibold">{s.title}</h3>
                                        <p className="mt-1 text-sm text-muted-foreground">{s.desc}</p>
                                        <div className="mt-4 flex items-center justify-between">
                                            <span className="font-serif text-lg font-bold text-primary">{s.price}</span>
                                            <button
                                                type="button"
                                                className="flex h-10 w-10 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-card"
                                            >
                                                <Plus className="h-5 w-5" />
                                            </button>
                                        </div>
                                    </div>
                                </Card>
                            ))}
                        </div>
                    )}

                    {tab === 'amenities' && (
                        <div className="space-y-6">
                            <Card className="border-accent/40 bg-gradient-to-br from-card to-accent/10">
                                <div className="flex gap-3">
                                    <Gift className="h-8 w-8 shrink-0 text-accent" />
                                    <div>
                                        <p className="font-serif text-lg font-semibold">Complimentary amenities</p>
                                        <p className="mt-1 text-sm text-muted-foreground">Enjoy these items delivered to your room.</p>
                                    </div>
                                </div>
                            </Card>
                            <div className="grid grid-cols-2 gap-3">
                                {freeAmenities.map((a) => (
                                    <Card key={a.name} className="p-4 text-center">
                                        <p className="text-4xl">{a.emoji}</p>
                                        <p className="mt-2 font-serif text-sm font-semibold leading-tight">{a.name}</p>
                                        <p className="text-xs text-muted-foreground">{a.servings} included</p>
                                        <div className="mt-3 flex items-center justify-center gap-2">
                                            <button type="button" className="rounded-full border border-border p-1">
                                                <Minus className="h-4 w-4" />
                                            </button>
                                            <span className="w-6 text-center text-sm font-semibold">1</span>
                                            <button type="button" className="rounded-full border border-border p-1">
                                                <Plus className="h-4 w-4" />
                                            </button>
                                        </div>
                                        <Button variant="secondary" className="mt-3 w-full py-2 text-sm">
                                            Request
                                        </Button>
                                    </Card>
                                ))}
                            </div>
                            <div>
                                <p className="mb-2 text-xs font-semibold uppercase text-muted-foreground">Your requests</p>
                                <Card className="p-4">
                                    <p className="font-medium text-foreground">Continental breakfast ×2</p>
                                    <p className="text-xs text-muted-foreground">Requested · 8:30 AM</p>
                                    <Badge variant="pending" className="mt-2">
                                        Pending
                                    </Badge>
                                </Card>
                            </div>
                        </div>
                    )}

                    {tab === 'chat' && (
                        <div className="space-y-4">
                            <p className="text-center text-sm text-muted-foreground">Available 24/7</p>
                            <div className="space-y-3">
                                <div className="max-w-[85%] rounded-2xl rounded-bl-sm bg-card px-4 py-3 shadow-card">
                                    <p className="text-sm text-foreground">Hello! How can we assist you today?</p>
                                    <p className="mt-1 text-[10px] text-muted-foreground">9:30 AM</p>
                                </div>
                                <div className="ml-auto max-w-[85%] rounded-2xl rounded-br-sm bg-primary px-4 py-3 text-primary-foreground shadow-card">
                                    <p className="text-sm">I need extra towels please.</p>
                                    <p className="mt-1 text-[10px] text-primary-foreground/80">9:32 AM</p>
                                </div>
                                <div className="max-w-[90%] rounded-2xl border border-accent/30 bg-gradient-to-br from-amber-50 to-orange-50 px-4 py-3 shadow-card">
                                    <p className="flex items-center gap-2 text-sm font-medium text-amber-900">
                                        <Gift className="h-4 w-4" />
                                        Amenity request
                                    </p>
                                    <p className="mt-1 text-sm text-amber-950">2× Continental breakfast</p>
                                    <p className="mt-1 text-[10px] text-amber-800/80">9:35 AM</p>
                                </div>
                            </div>
                            <div className="fixed bottom-0 left-0 right-0 border-t border-border bg-card/95 p-4 backdrop-blur-md">
                                <div className="mx-auto flex max-w-lg gap-2">
                                    <input
                                        type="text"
                                        placeholder="Type a message…"
                                        className="min-h-[44px] flex-1 rounded-full border border-border bg-background px-4 text-base outline-none focus:border-primary"
                                    />
                                    <Button className="shrink-0 px-5">Send</Button>
                                </div>
                            </div>
                        </div>
                    )}
                </main>

                {cartOpen && (
                    <div className="fixed inset-0 z-50 flex items-end justify-center bg-foreground/40 backdrop-blur-sm sm:items-center">
                        <div className="max-h-[90vh] w-full max-w-lg rounded-t-3xl bg-card p-6 shadow-xl sm:rounded-3xl">
                            <div className="mb-4 flex items-center justify-between">
                                <h3 className="font-serif text-xl font-semibold">Your request</h3>
                                <button type="button" onClick={() => setCartOpen(false)} className="text-muted-foreground hover:text-foreground">
                                    ✕
                                </button>
                            </div>
                            <p className="text-sm text-muted-foreground">Cart items connect to your property POS when configured.</p>
                            <Button className="mt-6 w-full" onClick={() => setCartOpen(false)}>
                                Confirm request
                            </Button>
                        </div>
                    </div>
                )}
            </div>
        </>
    );
}
