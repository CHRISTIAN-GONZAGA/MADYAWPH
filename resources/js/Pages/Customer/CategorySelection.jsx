import { Head, Link } from '@inertiajs/react';
import { motion } from 'motion/react';
import BackButton from '../../Components/BackButton';

const CATEGORY_IMAGES = {
    king: 'https://images.unsplash.com/photo-1631049035182-249067d7618e?auto=format&fit=crop&w=1200&q=80',
    queen: 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1200&q=80',
    double: 'https://images.unsplash.com/photo-1616594039964-3cf4ed4784ea?auto=format&fit=crop&w=1200&q=80',
    suite: 'https://images.unsplash.com/photo-1590490359854-dfba19688d70?auto=format&fit=crop&w=1200&q=80',
    deluxe: 'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=1200&q=80',
    family: 'https://images.unsplash.com/photo-1521783988139-89397d761dce?auto=format&fit=crop&w=1200&q=80',
    executive: 'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1200&q=80',
    presidential: 'https://images.unsplash.com/photo-1445019980597-93fa8acb246c?auto=format&fit=crop&w=1200&q=80',
};

export default function CategorySelection({ hotel = null, categories = [] }) {
    return (
        <div className="min-h-screen bg-background px-4 py-8">
            <Head title="Room Categories" />
            <div className="max-w-4xl mx-auto">
                <div className="mb-4">
                    <BackButton fallback="/auth/select" />
                </div>
                <h1 className="font-serif text-3xl mb-2">{hotel?.name ?? 'Hotel'}</h1>
                <p className="text-muted-foreground mb-6">Choose a room category</p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    {categories.map((category, index) => (
                        <motion.div key={category.id} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * 0.05 }}>
                            <Link href={`/customer/categories/${category.id}/rooms`} className="group block bg-card border border-border rounded-xl overflow-hidden hover:border-primary">
                                <div className="h-36 overflow-hidden">
                                    <img
                                        src={CATEGORY_IMAGES[category.id] ?? CATEGORY_IMAGES.suite}
                                        alt={`${category.name} room category`}
                                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                                    />
                                </div>
                                <div className="p-4">
                                    <p className="font-medium">{category.name}</p>
                                    <p className="text-sm text-muted-foreground">{category.description}</p>
                                </div>
                            </Link>
                        </motion.div>
                    ))}
                    {categories.length === 0 && <p className="text-sm text-muted-foreground">No categories available.</p>}
                </div>
            </div>
        </div>
    );
}
