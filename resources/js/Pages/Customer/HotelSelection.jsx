import { Head, Link } from '@inertiajs/react';
import { motion } from 'motion/react';
import BackButton from '../../Components/BackButton';

const HOTEL_IMAGES = [
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1551776235-dde6d4829808?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=1200&q=80',
];

export default function HotelSelection({ hotels = [] }) {
    return (
        <div className="min-h-screen bg-background px-4 py-8">
            <Head title="Select Hotel" />
            <div className="max-w-4xl mx-auto">
                <div className="mb-4">
                    <BackButton fallback="/auth/select" />
                </div>
                <h1 className="font-serif text-3xl mb-2">Select a Hotel</h1>
                <p className="text-muted-foreground mb-6">Choose where you want to stay and explore available room categories.</p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    {hotels.map((hotel, index) => (
                        <motion.div key={hotel.id} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.05 }}>
                            <Link href={`/customer/hotels/${hotel.id}/categories`} className="group block bg-card border border-border rounded-xl overflow-hidden hover:border-primary transition-all">
                                <div className="h-40 overflow-hidden">
                                    <img src={HOTEL_IMAGES[index % HOTEL_IMAGES.length]} alt={`${hotel.name} preview`} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" />
                                </div>
                                <div className="p-4">
                                    <p className="font-medium text-lg">{hotel.name}</p>
                                    <p className="text-sm text-muted-foreground">{hotel.location}</p>
                                </div>
                            </Link>
                        </motion.div>
                    ))}
                    {hotels.length === 0 && <p className="text-sm text-muted-foreground">No hotels available.</p>}
                </div>
            </div>
        </div>
    );
}
