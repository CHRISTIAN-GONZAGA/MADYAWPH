import { useForm, router } from '@inertiajs/react';
import {
    ArrowLeft,
    Briefcase,
    Building2,
    DoorOpen,
    Sparkles,
    Users,
} from 'lucide-react';
import { useState } from 'react';
import Button from '../Components/Button';
import BackButton from '../Components/BackButton';
import Card from '../Components/Card';
import Input from '../Components/Input';

const categories = [
    {
        key: 'public',
        title: 'Public customer',
        description: 'Browse & book rooms',
        icon: Users,
    },
    {
        key: 'admin',
        title: 'Admin',
        description: 'Hotel management',
        icon: Building2,
    },
    {
        key: 'staff',
        title: 'Staff',
        description: 'Employee portal',
        icon: Briefcase,
    },
    {
        key: 'guest',
        title: 'Guest in-house',
        description: 'Room access',
        icon: DoorOpen,
    },
];

export default function Login({ hotels }) {
    const [step, setStep] = useState('categories');

    const { data, setData, post, processing, errors } = useForm({
        hotel_id: hotels[0]?.id ?? '',
        role: 'admin',
        email: '',
        password: '',
    });

    const guestForm = useForm({
        room_number: '',
        room_password: '',
    });

    const submitStaff = (e) => {
        e.preventDefault();
        post('/login');
    };

    const submitPublic = (e) => {
        e.preventDefault();
        post('/login');
    };

    const openGuestRoom = (e) => {
        e.preventDefault();
        router.get('/guest-room', {
            room: guestForm.data.room_number || '101',
        });
    };

    return (
        <div className="min-h-screen bg-linen px-4 py-10">
            <div className="mx-auto w-full max-w-lg">
                <BackButton fallback="/login" className="mb-4" />
                {step === 'categories' && (
                    <div>
                        <div className="mb-8 text-center">
                            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg">
                                <Sparkles className="h-8 w-8" />
                            </div>
                            <h1 className="font-serif text-3xl font-bold text-foreground">Multi-Hotel Management</h1>
                            <p className="mt-2 text-base text-muted-foreground">Choose your access level</p>
                        </div>
                        <div className="flex flex-col gap-4">
                            {categories.map(({ key, title, description, icon: Icon }) => (
                                <Card
                                    key={key}
                                    interactive
                                    className="cursor-pointer border-2 border-border bg-card p-6"
                                    onClick={() => {
                                        if (key === 'public') {
                                            setData('role', 'customer');
                                            setStep('public');
                                        } else if (key === 'guest') {
                                            setStep('guest');
                                        } else {
                                            setData('role', key);
                                            setData('email', '');
                                            setData('password', '');
                                            setStep(key);
                                        }
                                    }}
                                >
                                    <div className="flex items-start gap-4">
                                        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                                            <Icon className="h-6 w-6" strokeWidth={1.75} />
                                        </div>
                                        <div>
                                            <p className="font-serif text-xl font-semibold text-foreground">{title}</p>
                                            <p className="mt-1 text-sm text-muted-foreground">{description}</p>
                                        </div>
                                    </div>
                                </Card>
                            ))}
                        </div>
                    </div>
                )}

                {step === 'admin' && (
                    <form onSubmit={submitStaff} className="space-y-6">
                        <button
                            type="button"
                            onClick={() => setStep('categories')}
                            className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-primary"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Back
                        </button>
                        <div className="text-center">
                            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <Building2 className="h-7 w-7" />
                            </div>
                            <h2 className="font-serif text-2xl font-bold">Administrator login</h2>
                            <p className="mt-1 text-sm text-muted-foreground">Welcome back. Use your admin account credentials.</p>
                        </div>
                        <div>
                            <label className="mb-1 block text-sm font-medium">Hotel</label>
                            <select
                                className="w-full border-0 border-b-2 border-border bg-transparent py-3 text-base outline-none focus:border-primary"
                                value={data.hotel_id}
                                onChange={(e) => setData('hotel_id', e.target.value)}
                            >
                                {hotels.map((hotel) => (
                                    <option key={hotel.id} value={hotel.id}>
                                        {hotel.name} — {hotel.location}
                                    </option>
                                ))}
                            </select>
                        </div>
                        <Input label="Email address" name="email" type="email" value={data.email} onChange={(e) => setData('email', e.target.value)} error={errors.email} autoComplete="email" />
                        <Input
                            label="Password"
                            name="password"
                            type="password"
                            value={data.password}
                            onChange={(e) => setData('password', e.target.value)}
                            error={errors.password}
                            autoComplete="current-password"
                        />
                        <Button type="submit" className="w-full" disabled={processing}>
                            Login
                        </Button>
                        <p className="text-center text-sm text-muted-foreground">Forgot password? Contact your administrator.</p>
                    </form>
                )}

                {step === 'staff' && (
                    <form onSubmit={submitStaff} className="space-y-6">
                        <button
                            type="button"
                            onClick={() => setStep('categories')}
                            className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-primary"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Back
                        </button>
                        <div className="text-center">
                            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <Briefcase className="h-7 w-7" />
                            </div>
                            <h2 className="font-serif text-2xl font-bold">Staff login</h2>
                            <p className="mt-1 text-sm text-muted-foreground">Employee portal. Use your staff account credentials.</p>
                        </div>
                        <div>
                            <label className="mb-1 block text-sm font-medium">Hotel</label>
                            <select
                                className="w-full border-0 border-b-2 border-border bg-transparent py-3 text-base outline-none focus:border-primary"
                                value={data.hotel_id}
                                onChange={(e) => setData('hotel_id', e.target.value)}
                            >
                                {hotels.map((hotel) => (
                                    <option key={hotel.id} value={hotel.id}>
                                        {hotel.name} — {hotel.location}
                                    </option>
                                ))}
                            </select>
                        </div>
                        <Input label="Email address" type="email" value={data.email} onChange={(e) => setData('email', e.target.value)} error={errors.email} />
                        <Input label="Password" type="password" value={data.password} onChange={(e) => setData('password', e.target.value)} error={errors.password} />
                        <Button type="submit" className="w-full" disabled={processing}>
                            Login
                        </Button>
                    </form>
                )}

                {step === 'public' && (
                    <form onSubmit={submitPublic} className="space-y-6">
                        <button
                            type="button"
                            onClick={() => setStep('categories')}
                            className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-primary"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Back
                        </button>
                        <div className="text-center">
                            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <Users className="h-7 w-7" />
                            </div>
                            <h2 className="font-serif text-2xl font-bold">Browse & book</h2>
                            <p className="mt-1 text-sm text-muted-foreground">Select a hotel to continue</p>
                        </div>
                        <div>
                            <label className="mb-1 block text-sm font-medium">Hotel</label>
                            <select
                                className="w-full border-0 border-b-2 border-border bg-transparent py-3 text-base outline-none focus:border-primary"
                                value={data.hotel_id}
                                onChange={(e) => setData('hotel_id', e.target.value)}
                            >
                                {hotels.map((hotel) => (
                                    <option key={hotel.id} value={hotel.id}>
                                        {hotel.name} — {hotel.location}
                                    </option>
                                ))}
                            </select>
                        </div>
                        <Button type="submit" className="w-full" disabled={processing}>
                            Continue to booking
                        </Button>
                    </form>
                )}

                {step === 'guest' && (
                    <form onSubmit={openGuestRoom} className="space-y-6">
                        <button
                            type="button"
                            onClick={() => setStep('categories')}
                            className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-primary"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Back
                        </button>
                        <div className="text-center">
                            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <DoorOpen className="h-7 w-7" />
                            </div>
                            <h2 className="font-serif text-2xl font-bold">Guest room access</h2>
                            <p className="mt-1 text-sm text-muted-foreground">Enter your room</p>
                        </div>
                        <Input
                            label="Room number"
                            value={guestForm.data.room_number}
                            onChange={(e) => guestForm.setData('room_number', e.target.value)}
                            placeholder="e.g. 101"
                        />
                        <Input
                            label="Room password"
                            type="password"
                            value={guestForm.data.room_password}
                            onChange={(e) => guestForm.setData('room_password', e.target.value)}
                            placeholder="From your welcome card"
                        />
                        <p className="text-center text-sm text-muted-foreground">Check your welcome card for room access credentials.</p>
                        <Button type="submit" className="w-full">
                            Access room
                        </Button>
                    </form>
                )}
            </div>
        </div>
    );
}
