import { Link, usePage } from '@inertiajs/react';
import { motion } from 'motion/react';
import { Users, Hotel as HotelIcon, UserCog, DoorOpen } from 'lucide-react';
import BackButton from '../../Components/BackButton';

export default function CategorySelection() {
    const { activeHotelId = '' } = usePage().props;
    const hotelQuery = activeHotelId ? `?hotel=${encodeURIComponent(activeHotelId)}` : '';
    const categories = [
        { id: 'customer', label: 'Public Customer', subtitle: 'Browse & Book Rooms', icon: Users, href: `/customer/categories${hotelQuery}` },
        { id: 'admin', label: 'Admin', subtitle: 'Hotel Management', icon: HotelIcon, href: `/auth/admin${hotelQuery}` },
        { id: 'staff', label: 'Staff', subtitle: 'Employee Portal', icon: UserCog, href: `/auth/staff${hotelQuery}` },
        { id: 'guest', label: 'Guest In-House', subtitle: 'Room Access', icon: DoorOpen, href: `/auth/guest${hotelQuery}` },
    ];

    return (
        <div className="min-h-screen bg-background relative overflow-hidden font-sans">
            <div className="absolute inset-0 opacity-10 pointer-events-none bg-linen" />
            <div className="relative z-10 min-h-screen flex flex-col items-center justify-center px-4 sm:px-6 py-12">
                <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} className="text-center mb-12">
                    <div className="flex justify-center mb-5">
                        <BackButton fallback="/auth/hotel" />
                    </div>
                    <div className="w-16 h-16 mx-auto mb-4 bg-primary rounded-2xl flex items-center justify-center shadow-lg">
                        <HotelIcon className="w-8 h-8 text-primary-foreground" />
                    </div>
                    <h1 className="font-serif text-4xl sm:text-5xl text-foreground mb-3">MADYAW</h1>
                    <p className="text-muted-foreground text-sm sm:text-base">Choose Your Access Level</p>
                </motion.div>

                <div className="w-full max-w-2xl grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">
                    {categories.map((category, index) => (
                        <motion.div key={category.id} initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.1 }}>
                            <Link href={category.href} className="block bg-card border border-border rounded-2xl p-6 sm:p-8 shadow-sm hover:shadow-md transition-all">
                                <div className="flex flex-col items-center text-center gap-3">
                                    <div className="w-14 h-14 bg-primary/10 rounded-full flex items-center justify-center">
                                        <category.icon className="w-7 h-7 text-primary" />
                                    </div>
                                    <div>
                                        <h3 className="font-serif text-xl text-foreground mb-1">{category.label}</h3>
                                        <p className="text-sm text-muted-foreground">{category.subtitle}</p>
                                    </div>
                                </div>
                            </Link>
                        </motion.div>
                    ))}
                </div>
            </div>
        </div>
    );
}
