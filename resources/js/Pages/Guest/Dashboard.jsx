import { useEffect, useMemo, useState } from 'react';
import { Head, router } from '@inertiajs/react';
import { motion, AnimatePresence } from 'motion/react';
import axios from 'axios';
import { Gift, Sparkles, MessageCircle } from 'lucide-react';
import GuestLayout from '../../Layouts/GuestLayout';
import AmenityCard from '../../Components/Guest/AmenityCard';
import ShoppingCart from '../../Components/Guest/ShoppingCart';
import BackButton from '../../Components/BackButton';

const FREE_AMENITIES = [
    { type: 'breakfast', name: 'Continental Breakfast', description: 'Complimentary breakfast buffet', icon: '🍳' },
    { type: 'water', name: 'Bottled Water', description: '2 bottles of premium water', icon: '💧' },
    { type: 'towels', name: 'Extra Towels', description: 'Fresh towels and linens', icon: '🧺' },
    { type: 'toiletries', name: 'Toiletries Set', description: 'Premium bathroom amenities', icon: '🧴' },
];
const BREAKFAST_MENU = ['Tapsilog', 'Tosilog', 'Hotdog with Rice', 'Longsilog', 'Bangsilog'];

export default function GuestDashboard({ auth, roomInfo = {}, services = [], amenityClaims = [] }) {
    const [activeTab, setActiveTab] = useState('services');
    const [amenityQuantities, setAmenityQuantities] = useState({ breakfast: 1, water: 1, towels: 1, toiletries: 1 });
    const [chatMessage, setChatMessage] = useState('');
    const [sendingChat, setSendingChat] = useState(false);
    const [chatImageFile, setChatImageFile] = useState(null);
    const [extendNights, setExtendNights] = useState(1);
    const [showBreakfastModal, setShowBreakfastModal] = useState(false);
    const [breakfastItem, setBreakfastItem] = useState(BREAKFAST_MENU[0]);
    const [showCheckoutWarning, setShowCheckoutWarning] = useState(false);
    const [extendingStay, setExtendingStay] = useState(false);
    const [showReviewPrompt, setShowReviewPrompt] = useState(Boolean(roomInfo?.showReviewPrompt));
    const [reviewRating, setReviewRating] = useState(5);
    const [reviewComment, setReviewComment] = useState('');

    const checkoutTime = roomInfo?.checkOutAt ? new Date(roomInfo.checkOutAt) : null;

    useEffect(() => {
        if (!checkoutTime) return null;
        const now = new Date();
        const diffMinutes = (checkoutTime.getTime() - now.getTime()) / 60000;
        if (diffMinutes <= 60 && diffMinutes > 0) {
            setShowCheckoutWarning(true);
            try {
                const ctx = new (window.AudioContext || window.webkitAudioContext)();
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.type = 'sine';
                osc.frequency.value = 880;
                gain.gain.value = 0.02;
                osc.start();
                setTimeout(() => osc.stop(), 220);
            } catch (_err) {
                // silent fallback
            }
        }
        return undefined;
    }, [roomInfo?.checkOutAt]);

    async function handleClaimAmenity(amenityType, amenityName, quantity) {
        if (amenityType === 'breakfast') {
            setShowBreakfastModal(true);
            return;
        }
        try {
            await axios.post('/guest/amenities/claim', { amenityType, amenityName, quantity });
            try {
                await axios.post('/guest/chat/messages', { message: `Amenity Request: ${quantity}x ${amenityName}` });
            } catch (_chatError) {
                // Chat can fail without breaking amenity claims.
            }
            router.reload({ only: ['amenityClaims'] });
        } catch (_error) {
            alert('Unable to submit amenity request right now.');
        }
    }

    async function submitBreakfastChoice() {
        await handleClaimAmenity('breakfast', `Continental Breakfast - ${breakfastItem}`, amenityQuantities.breakfast ?? 1);
        setShowBreakfastModal(false);
    }

    async function sendGuestChat() {
        if (!chatMessage.trim() && !chatImageFile) return;
        setSendingChat(true);
        try {
            const payload = new FormData();
            payload.append('message', chatMessage.trim() || 'Photo message');
            if (chatImageFile) payload.append('image_file', chatImageFile);
            await axios.post('/guest/chat/messages', payload, { headers: { 'Content-Type': 'multipart/form-data' } });
            setChatMessage('');
            setChatImageFile(null);
            alert('Message sent to concierge.');
        } catch (_error) {
            alert('Unable to send message right now.');
        } finally {
            setSendingChat(false);
        }
    }

    async function requestExtendStay() {
        setExtendingStay(true);
        try {
            const response = await axios.post('/guest/extend-stay', { nights: extendNights });
            alert(`Stay extended. New checkout: ${response.data.new_checkout_date}. Added fee: PHP ${Number(response.data.extension_fee ?? 0).toLocaleString()}`);
            router.reload({ only: ['roomInfo'] });
        } catch (_error) {
            alert('Unable to extend stay right now.');
        } finally {
            setExtendingStay(false);
        }
    }

    async function submitReview() {
        if (!roomInfo?.activeBookingId) return;
        try {
            await axios.post('/guest/review', {
                booking_id: roomInfo.activeBookingId,
                rating: reviewRating,
                comment: reviewComment.trim() || undefined,
            });
            setShowReviewPrompt(false);
            alert('Thank you for your review.');
        } catch (_error) {
            alert('Unable to submit review right now.');
        }
    }

    const selectedItems = useMemo(
        () => FREE_AMENITIES.map((a) => ({ type: a.type, name: a.name, quantity: amenityQuantities[a.type] ?? 1 })),
        [amenityQuantities],
    );

    return (
        <GuestLayout user={auth?.user} roomInfo={roomInfo}>
            <Head title="Guest Dashboard" />
            <div className="min-h-screen bg-background font-sans text-foreground relative">
                <div className="mb-4">
                    <BackButton fallback="/auth/guest" />
                </div>
                <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className="rounded-2xl border border-border bg-card p-4 sm:p-5 mb-5">
                    <h1 className="font-serif text-2xl">Welcome, {auth?.user?.name ?? 'Guest'}</h1>
                    <p className="text-sm text-muted-foreground mt-1">
                        Room {roomInfo?.roomNumber ?? '-'} • Enjoy in-room support and complimentary amenities.
                    </p>
                </motion.div>
                {showCheckoutWarning && (
                    <div className="mb-4 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-amber-800 text-sm">
                        Checkout warning: your checkout time is approaching. Please prepare for departure or request extension.
                    </div>
                )}
                <div className="flex gap-3 mb-6 border-b border-border overflow-x-auto">
                    <TabButton active={activeTab === 'services'} onClick={() => setActiveTab('services')} icon={Sparkles} label="In-Room Services" />
                    <TabButton active={activeTab === 'amenities'} onClick={() => setActiveTab('amenities')} icon={Gift} label="Free Amenities" />
                    <TabButton active={activeTab === 'chat'} onClick={() => setActiveTab('chat')} icon={MessageCircle} label="Concierge Chat" />
                </div>

                <AnimatePresence mode="wait">
                    {activeTab === 'services' && (
                        <motion.div key="services" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="bg-card border border-border rounded-2xl p-5">
                            <h2 className="font-serif text-xl mb-3">Services</h2>
                            {services.length === 0 ? (
                                <div className="grid sm:grid-cols-2 gap-3">
                                    {['Housekeeping Request', 'Laundry Pickup', 'Late Checkout', 'Wake-up Call'].map((service) => (
                                        <div key={service} className="rounded-xl border border-border bg-background p-3">
                                            <p className="font-medium text-sm">{service}</p>
                                            <button type="button" className="mt-2 text-xs px-3 py-1.5 rounded-full border border-primary text-primary hover:bg-primary/5">Request</button>
                                        </div>
                                    ))}
                                </div>
                            ) : services.map((service) => <p key={service.id}>{service.name}</p>)}
                            <div className="mt-4 rounded-xl border border-border bg-background p-3">
                                <p className="font-medium text-sm">Extend Stay (Auto Fee)</p>
                                <div className="mt-2 flex items-center gap-2">
                                    <input type="number" min="1" value={extendNights} onChange={(event) => setExtendNights(Number(event.target.value) || 1)} className="w-24 border border-border rounded-lg px-2 py-1 text-sm" />
                                    <button type="button" disabled={extendingStay} onClick={requestExtendStay} className="px-3 py-1.5 rounded-full border border-primary text-primary text-xs disabled:opacity-50">{extendingStay ? 'Processing...' : 'Request Extension'}</button>
                                </div>
                            </div>
                        </motion.div>
                    )}

                    {activeTab === 'amenities' && (
                        <motion.div key="amenities" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="space-y-6">
                            <div className="bg-card border border-border rounded-2xl p-5">
                                <h2 className="font-serif text-xl mb-2">Complimentary Amenities</h2>
                                <p className="text-sm text-muted-foreground">Request free amenities for your room.</p>
                            </div>
                            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                                {FREE_AMENITIES.map((amenity) => {
                                    const quantity = amenityQuantities[amenity.type] ?? 1;
                                    const alreadyClaimed = amenityClaims.some((claim) => claim.amenityType === amenity.type && claim.status === 'pending');
                                    return (
                                        <AmenityCard
                                            key={amenity.type}
                                            amenity={amenity}
                                            quantity={quantity}
                                            disabled={alreadyClaimed}
                                            onDecrement={() => setAmenityQuantities((prev) => ({ ...prev, [amenity.type]: Math.max(1, quantity - 1) }))}
                                            onIncrement={() => setAmenityQuantities((prev) => ({ ...prev, [amenity.type]: quantity + 1 }))}
                                            onRequest={() => handleClaimAmenity(amenity.type, amenity.name, quantity)}
                                        />
                                    );
                                })}
                            </div>
                            <ShoppingCart items={selectedItems} />
                        </motion.div>
                    )}

                    {activeTab === 'chat' && (
                        <motion.div key="chat" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="bg-card border border-border rounded-2xl p-5">
                            <h2 className="font-serif text-xl mb-2">Concierge Chat</h2>
                            <p className="text-sm text-muted-foreground mb-4">Send quick requests to the concierge desk.</p>
                            <div className="space-y-3">
                                <textarea
                                    value={chatMessage}
                                    onChange={(e) => setChatMessage(e.target.value)}
                                    rows={4}
                                    className="w-full border border-border rounded-xl bg-background px-3 py-2 text-sm"
                                    placeholder="Type your message..."
                                />
                                <input type="file" accept="image/*" capture="environment" onChange={(event) => setChatImageFile(event.target.files?.[0] ?? null)} className="w-full border border-border rounded-xl bg-background px-3 py-2 text-sm" />
                                <button
                                    type="button"
                                    onClick={sendGuestChat}
                                    disabled={sendingChat || (!chatMessage.trim() && !chatImageFile)}
                                    className="px-4 py-2 rounded-full bg-primary text-primary-foreground text-sm disabled:opacity-50"
                                >
                                    {sendingChat ? 'Sending...' : 'Send Message'}
                                </button>
                            </div>
                        </motion.div>
                    )}
                </AnimatePresence>
            </div>
            {showBreakfastModal && (
                <div className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center" onClick={() => setShowBreakfastModal(false)}>
                    <div className="w-full max-w-sm rounded-2xl border border-border bg-card p-4 space-y-3" onClick={(event) => event.stopPropagation()}>
                        <h3 className="font-serif text-lg">Choose Breakfast</h3>
                        <select value={breakfastItem} onChange={(event) => setBreakfastItem(event.target.value)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm">
                            {BREAKFAST_MENU.map((item) => <option key={item} value={item}>{item}</option>)}
                        </select>
                        <button type="button" onClick={submitBreakfastChoice} className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Add Breakfast</button>
                    </div>
                </div>
            )}
            {showReviewPrompt && (
                <div className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center" onClick={() => setShowReviewPrompt(false)}>
                    <div className="w-full max-w-md rounded-2xl border border-border bg-card p-4 space-y-3" onClick={(event) => event.stopPropagation()}>
                        <h3 className="font-serif text-lg">Rate Your Stay</h3>
                        <p className="text-sm text-muted-foreground">We would love your feedback after checkout.</p>
                        <select value={reviewRating} onChange={(event) => setReviewRating(Number(event.target.value) || 5)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm">
                            {[5, 4, 3, 2, 1].map((rating) => <option key={rating} value={rating}>{rating} Star{rating > 1 ? 's' : ''}</option>)}
                        </select>
                        <textarea value={reviewComment} onChange={(event) => setReviewComment(event.target.value)} className="w-full border border-border rounded-lg px-3 py-2 bg-background text-sm" rows={4} placeholder="Comment (optional)" />
                        <button type="button" onClick={submitReview} className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Submit Review</button>
                    </div>
                </div>
            )}
        </GuestLayout>
    );
}

function TabButton({ active, onClick, icon: Icon, label }) {
    return (
        <button type="button" onClick={onClick} className={`px-4 py-2 rounded-t-xl text-sm whitespace-nowrap inline-flex items-center gap-2 ${active ? 'bg-card border border-border border-b-card' : 'text-muted-foreground'}`}>
            <Icon className="w-4 h-4" />
            {label}
        </button>
    );
}
