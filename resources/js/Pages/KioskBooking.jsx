import { Head, router } from '@inertiajs/react';
import axios from 'axios';
import { Sparkles } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import BackButton from '../Components/BackButton';
import Button from '../Components/Button';
import Card from '../Components/Card';

const roomCategoryOrder = ['king', 'queen', 'single', 'double'];
const categoryImages = {
    king: 'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=1200&q=80',
    queen: 'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1200&q=80',
    single: 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1200&q=80',
    double: 'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=1200&q=80',
};

const toCategory = (roomType) => {
    const normalized = String(roomType ?? '').toLowerCase();
    if (normalized === 'suite') return 'king';
    if (normalized === 'deluxe') return 'queen';
    if (normalized === 'single' || normalized === 'double') return normalized;
    return 'single';
};

const categoryLabel = (category) => category.charAt(0).toUpperCase() + category.slice(1);

export default function KioskBooking({ hotelId = '', hotelName = '' }) {
    const [lockedHotelId, setLockedHotelId] = useState(hotelId ? String(hotelId) : '');
    const [rooms, setRooms] = useState([]);
    const [loading, setLoading] = useState(true);
    const [selectedCategory, setSelectedCategory] = useState('');

    useEffect(() => {
        if (typeof window === 'undefined') return;
        const stored = sessionStorage.getItem('kiosk_hotel_id');
        if (stored) {
            setLockedHotelId(stored);
            return;
        }

        if (hotelId) {
            const normalized = String(hotelId);
            sessionStorage.setItem('kiosk_hotel_id', normalized);
            setLockedHotelId(normalized);
        }
    }, [hotelId]);

    useEffect(() => {
        const fetchRooms = async () => {
            if (!lockedHotelId) {
                setRooms([]);
                setLoading(false);
                return;
            }

            setLoading(true);
            try {
                const response = await axios.get('/api/rooms/available', {
                    params: { hotel_id: lockedHotelId },
                });
                setRooms(Array.isArray(response.data) ? response.data : []);
            } finally {
                setLoading(false);
            }
        };

        fetchRooms();
    }, [lockedHotelId]);

    const categories = useMemo(() => {
        const categorySet = new Set(rooms.map((room) => toCategory(room.room_type)));
        return roomCategoryOrder.filter((category) => categorySet.has(category));
    }, [rooms]);

    useEffect(() => {
        if (!categories.length) return;
        if (selectedCategory && !categories.includes(selectedCategory)) {
            setSelectedCategory('');
        }
    }, [categories, selectedCategory]);

    const visibleRooms = useMemo(
        () => rooms.filter((room) => toCategory(room.room_type) === selectedCategory),
        [rooms, selectedCategory],
    );

    const startBooking = (room) => {
        router.get('/booking', {
            hotel_id: room.hotel_id ?? lockedHotelId,
            room_id: room.id,
            room_number: room.room_number,
            hotel_name: hotelName,
        });
    };

    const restartHotelSelection = () => {
        if (typeof window !== 'undefined') {
            sessionStorage.removeItem('kiosk_hotel_id');
        }
        router.visit('/login');
    };

    return (
        <>
            <Head title="Kiosk booking" />
            <div className="min-h-screen bg-linen px-4 py-8">
                <div className="mx-auto max-w-5xl">
                    <div className="mb-4 flex items-center justify-between">
                        <BackButton fallback="/login" />
                        <Button variant="secondary" className="px-4 py-2 text-sm" onClick={restartHotelSelection}>
                            Change hotel
                        </Button>
                    </div>
                    <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg">
                        <Sparkles className="h-9 w-9" />
                    </div>
                    <h1 className="text-center font-serif text-3xl font-bold text-foreground">Book your hotel room</h1>
                    <p className="mt-3 text-center text-muted-foreground">
                        {hotelName ? `${hotelName} room categories` : 'Select your room category to continue.'}
                    </p>

                    {!loading && categories.length > 0 && (
                        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                            {categories.map((category) => (
                                <button
                                    key={category}
                                    type="button"
                                    onClick={() => setSelectedCategory(category)}
                                    className={`overflow-hidden rounded-2xl border text-left transition ${
                                        selectedCategory === category
                                            ? 'border-primary shadow-lg ring-2 ring-primary/25'
                                            : 'border-border hover:border-primary/40'
                                    }`}
                                >
                                    <div className="relative h-28">
                                        <img src={categoryImages[category]} alt={`${categoryLabel(category)} room`} className="h-full w-full object-cover" />
                                        <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-black/10" />
                                        <p className="absolute bottom-2 left-3 font-serif text-lg font-bold text-white">
                                            {categoryLabel(category)}
                                        </p>
                                    </div>
                                </button>
                            ))}
                        </div>
                    )}

                    {loading && <p className="mt-8 text-center text-muted-foreground">Loading available rooms...</p>}

                    {!loading && !lockedHotelId && (
                        <Card className="mx-auto mt-8 max-w-xl text-center">
                            <p className="font-medium text-foreground">No hotel selected.</p>
                            <p className="mt-2 text-sm text-muted-foreground">Go back to login and choose a hotel first.</p>
                        </Card>
                    )}

                    {!loading && lockedHotelId && selectedCategory && visibleRooms.length === 0 && (
                        <Card className="mx-auto mt-8 max-w-xl text-center">
                            <p className="font-medium text-foreground">No {categoryLabel(selectedCategory)} rooms available right now.</p>
                            <p className="mt-2 text-sm text-muted-foreground">Try another category in this hotel.</p>
                        </Card>
                    )}

                    {!loading && selectedCategory && (
                        <section className="mt-8">
                            <div className="mb-4 flex items-center justify-between">
                                <h2 className="font-serif text-2xl font-semibold text-foreground">
                                    {categoryLabel(selectedCategory)} Rooms
                                </h2>
                                <Button variant="secondary" className="px-4 py-2 text-sm" onClick={() => setSelectedCategory('')}>
                                    Back to categories
                                </Button>
                            </div>

                            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                                {visibleRooms.map((room) => (
                                    <Card key={room.id} interactive className="border-2 border-border bg-card/95">
                                        <p className="font-serif text-2xl font-bold text-foreground">Room {room.room_number}</p>
                                        <p className="mt-1 text-sm text-muted-foreground">{categoryLabel(toCategory(room.room_type))} room</p>
                                        <p className="mt-3 text-sm text-muted-foreground">
                                            Rate:{' '}
                                            <span className="font-semibold text-foreground">
                                                {room.price_per_night ? `₱${room.price_per_night}` : 'Price on request'}
                                            </span>
                                        </p>
                                        <Button className="mt-4 w-full py-2 text-sm" onClick={() => startBooking(room)}>
                                            Book this room
                                        </Button>
                                    </Card>
                                ))}
                            </div>
                        </section>
                    )}
                </div>
            </div>
        </>
    );
}
