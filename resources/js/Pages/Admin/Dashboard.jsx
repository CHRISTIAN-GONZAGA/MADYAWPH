import { useState } from 'react';
import { Head, router } from '@inertiajs/react';
import { motion } from 'motion/react';
import axios from 'axios';
import AdminLayout from '../../Layouts/AdminLayout';
import RoomManagement from '../../Components/Admin/RoomManagement';
import AmenityRequestList from '../../Components/Admin/AmenityRequestList';
import QuickActions from '../../Components/Admin/QuickActions';
import BackButton from '../../Components/BackButton';
import { Bell, Activity, MessageCircle, ClipboardList, BookOpenText, Users, ShieldAlert, BarChart3, Eye, EyeOff } from 'lucide-react';

export default function Dashboard({ auth, rooms = [], credits = null, amenityClaims = [], tasks = [], staff = [], categories = [], activityLogs = [], guestMessages = [], theme = null, reservations = [], reminders = [], reviews = [], transfers = [] }) {
    const [activeTab, setActiveTab] = useState('overview');
    const [roomStatusFilter, setRoomStatusFilter] = useState('all');
    const [roomTypeFilter, setRoomTypeFilter] = useState('all');
    const [floorFilter, setFloorFilter] = useState('all');
    const [replyByMessage, setReplyByMessage] = useState({});
    const [categoryForm, setCategoryForm] = useState({ name: '', description: '', default_price: '' });
    const [roomForm, setRoomForm] = useState({ category_id: '', display_name: '', room_number: '', room_type: 'Single', price_per_night: '' });
    const [staffForm, setStaffForm] = useState({ name: '', role: 'receptionist', username: '', password: '' });
    const [passwordForm, setPasswordForm] = useState({ code: '', new_password: '', new_password_confirmation: '' });
    const [showStaffPassword, setShowStaffPassword] = useState(false);
    const [showAdminNewPassword, setShowAdminNewPassword] = useState(false);
    const [showAdminConfirmPassword, setShowAdminConfirmPassword] = useState(false);
    const pendingAmenityClaims = amenityClaims.filter((claim) => claim.status === 'pending');
    const pendingTasksCount = tasks.filter((t) => t.status === 'pending').length;
    const unreadMessages = guestMessages.filter((message) => !message.is_read).length;
    const totalNotifications = pendingAmenityClaims.length + pendingTasksCount + unreadMessages;
    const filteredRooms = rooms.filter((room) => {
        const status = room.status?.value ?? room.status ?? 'available';
        const type = room.room_type?.value ?? room.room_type ?? room.category ?? 'Uncategorized';
        const floor = String(room.floor ?? 1);
        return (roomStatusFilter === 'all' || status === roomStatusFilter)
            && (roomTypeFilter === 'all' || type === roomTypeFilter)
            && (floorFilter === 'all' || floor === floorFilter);
    });
    const totalGuests = rooms.filter((room) => (room.status?.value ?? room.status) === 'booked').length;
    const totalRevenue = rooms.reduce((sum, room) => sum + Number(room.latest_booking?.total_amount ?? 0), 0);
    const bookingPoints = rooms
        .map((room) => room.latest_booking)
        .filter(Boolean)
        .map((booking) => ({
            date: new Date(booking.created_at ?? booking.check_in_date ?? Date.now()),
            amount: Number(booking.total_amount ?? 0),
        }));
    const now = new Date();
    const summaryPeriods = [
        { id: 'day', label: 'Today', check: (item) => item.date.toDateString() === now.toDateString() },
        { id: 'week', label: 'This Week', check: (item) => (now - item.date) / (1000 * 60 * 60 * 24) <= 7 },
        { id: 'month', label: 'This Month', check: (item) => item.date.getMonth() === now.getMonth() && item.date.getFullYear() === now.getFullYear() },
        { id: 'year', label: 'This Year', check: (item) => item.date.getFullYear() === now.getFullYear() },
    ];
    const salesSummary = summaryPeriods.map((period) => {
        const items = bookingPoints.filter(period.check);
        return {
            ...period,
            bookings: items.length,
            amount: items.reduce((sum, item) => sum + item.amount, 0),
        };
    });

    return (
        <AdminLayout user={auth?.user} credits={credits} theme={theme}>
            <Head title="Admin Dashboard" />
            <div className="space-y-6">
                <motion.header initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} className="bg-card border border-border rounded-2xl p-4 sm:p-6">
                    <div className="mb-4">
                        <BackButton fallback="/admin/dashboard" />
                    </div>
                    <div className="flex flex-wrap items-center justify-between gap-4">
                        <div>
                            <h2 className="font-serif text-2xl">Administrator Dashboard</h2>
                            <p className="text-sm text-muted-foreground">{auth?.user?.hotelName ?? 'Hotel'}</p>
                        </div>
                        <div className="flex items-center gap-2">
                            <button onClick={() => setActiveTab('overview')} className="relative p-2 bg-muted rounded-full">
                                <Bell className="w-4 h-4" />
                                {totalNotifications > 0 && (
                                    <span className="absolute -top-1 -right-1 px-1.5 py-0.5 bg-destructive text-destructive-foreground text-[10px] rounded-full">{totalNotifications > 9 ? '9+' : totalNotifications}</span>
                                )}
                            </button>
                        </div>
                    </div>
                    <div className="flex gap-2 mt-4 overflow-x-auto pb-1 -mx-1 px-1">
                        {[
                            { id: 'overview', label: 'Summary', icon: Activity },
                            { id: 'chat', label: `Chat${unreadMessages ? ` (${unreadMessages})` : ''}`, icon: MessageCircle },
                            { id: 'rooms', label: 'Rooms', icon: Activity },
                            { id: 'guests', label: 'Guests', icon: Users },
                            { id: 'tasks', label: 'Tasks', icon: ClipboardList },
                            { id: 'logs', label: 'Logs', icon: BookOpenText },
                            { id: 'staff', label: 'Staff', icon: Users },
                            { id: 'setup', label: 'Setup', icon: BarChart3 },
                            { id: 'sos', label: 'SOS', icon: ShieldAlert },
                            { id: 'sales', label: 'Sales', icon: BarChart3 },
                        ].map((tab) => (
                            <button
                                key={tab.id}
                                onClick={() => setActiveTab(tab.id)}
                                className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap ${activeTab === tab.id ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}
                            >
                                {tab.label}
                            </button>
                        ))}
                    </div>
                </motion.header>

                {activeTab === 'overview' && (
                    <div className="space-y-6">
                        <section className="grid grid-cols-2 lg:grid-cols-6 gap-3">
                            <MetricCard label="Total Rooms" value={rooms.length} onClick={() => { setActiveTab('rooms'); setRoomStatusFilter('all'); }} />
                            <MetricCard label="Booked" value={rooms.filter((room) => (room.status?.value ?? room.status) === 'booked').length} onClick={() => { setActiveTab('rooms'); setRoomStatusFilter('booked'); }} />
                            <MetricCard label="Available" value={rooms.filter((room) => (room.status?.value ?? room.status) === 'available').length} onClick={() => { setActiveTab('rooms'); setRoomStatusFilter('available'); }} />
                            <MetricCard label="Maintenance" value={rooms.filter((room) => (room.status?.value ?? room.status) === 'maintenance').length} onClick={() => { setActiveTab('rooms'); setRoomStatusFilter('maintenance'); }} />
                            <MetricCard label="Guests" value={totalGuests} onClick={() => setActiveTab('guests')} />
                            <MetricCard label="Revenue" value={`PHP ${totalRevenue.toLocaleString()}`} />
                        </section>
                        <QuickActions onNavigate={setActiveTab} pendingTasksCount={pendingTasksCount} />
                        <RoomManagement rooms={filteredRooms} />
                        <AmenityRequestList claims={pendingAmenityClaims} />
                    </div>
                )}

                {activeTab === 'chat' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Guest Chat Messages {unreadMessages > 0 ? `(${unreadMessages} unread)` : ''}</h3>
                        {guestMessages.length === 0 ? (
                            <p className="text-sm text-muted-foreground">No guest messages yet.</p>
                        ) : (
                            <div className="space-y-2 max-h-96 overflow-auto">
                                {guestMessages.map((message) => (
                                    <div key={message.id} className={`border border-border rounded-lg p-3 ${message.is_read ? '' : 'bg-primary/5'}`}>
                                        <p className="text-sm font-semibold">ROOM {message.room_number ?? '-'} - {message.guest_name ?? 'Guest'}</p>
                                        <p className="text-sm">{message.message}</p>
                                        {message.attachment_url && <img src={message.attachment_url} alt="attachment" className="mt-2 rounded-lg max-h-40 w-auto" />}
                                        <div className="mt-2 flex gap-2">
                                            <input
                                                value={replyByMessage[message.id]?.text ?? ''}
                                                onChange={(event) => setReplyByMessage((prev) => ({ ...prev, [message.id]: { ...(prev[message.id] ?? {}), text: event.target.value } }))}
                                                className="flex-1 border border-border rounded-lg px-2 py-1 text-xs bg-background"
                                                placeholder="Reply to guest"
                                            />
                                            <button
                                                type="button"
                                                className="px-2 py-1 text-xs rounded-lg bg-primary text-primary-foreground"
                                                onClick={async () => {
                                                    const payload = replyByMessage[message.id] ?? {};
                                                    if (!payload.text?.trim() && !payload.file) return;
                                                    const form = new FormData();
                                                    form.append('room_id', message.room_id);
                                                    form.append('room_number', message.room_number);
                                                    form.append('guest_name', message.guest_name ?? 'Guest');
                                                    form.append('message', payload.text?.trim() || 'Photo reply');
                                                    if (payload.file) form.append('image_file', payload.file);
                                                    await axios.post('/admin/chat/reply', form, { headers: { 'Content-Type': 'multipart/form-data' } });
                                                    setReplyByMessage((prev) => ({ ...prev, [message.id]: { text: '', file: null } }));
                                                    router.reload({ only: ['guestMessages', 'activityLogs'] });
                                                }}
                                            >
                                                Reply
                                            </button>
                                        </div>
                                        <input type="file" accept="image/*" capture="environment" onChange={(event) => setReplyByMessage((prev) => ({ ...prev, [message.id]: { ...(prev[message.id] ?? {}), file: event.target.files?.[0] ?? null } }))} className="mt-2 w-full border border-border rounded-lg px-2 py-1 text-xs bg-background" />
                                    </div>
                                ))}
                            </div>
                        )}
                    </section>
                )}

                {activeTab === 'rooms' && (
                    <section className="bg-card border border-border rounded-2xl p-5 space-y-3">
                        <h3 className="font-serif text-xl">Manage Rooms</h3>
                        <div className="grid sm:grid-cols-3 gap-2">
                            <select value={floorFilter} onChange={(event) => setFloorFilter(event.target.value)} className="border border-border rounded-lg px-3 py-2 bg-background text-sm">
                                <option value="all">All Floors</option>
                                {[...new Set(rooms.map((room) => String(room.floor ?? 1)))].map((floor) => <option key={floor} value={floor}>Floor {floor}</option>)}
                            </select>
                            <select value={roomStatusFilter} onChange={(event) => setRoomStatusFilter(event.target.value)} className="border border-border rounded-lg px-3 py-2 bg-background text-sm">
                                <option value="all">All Status</option>
                                <option value="available">Available</option>
                                <option value="booked">Booked</option>
                                <option value="maintenance">Maintenance</option>
                                <option value="reserved">Reserved</option>
                            </select>
                            <select value={roomTypeFilter} onChange={(event) => setRoomTypeFilter(event.target.value)} className="border border-border rounded-lg px-3 py-2 bg-background text-sm">
                                <option value="all">All Room Types</option>
                                {[...new Set(rooms.map((room) => room.room_type?.value ?? room.room_type ?? room.category ?? 'Uncategorized'))].map((type) => <option key={type} value={type}>{type}</option>)}
                            </select>
                        </div>
                        <RoomManagement rooms={filteredRooms} allRooms={rooms} />
                    </section>
                )}

                {activeTab === 'guests' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Current Guests</h3>
                        <div className="space-y-2">
                            {rooms.filter((room) => (room.status?.value ?? room.status) === 'booked').map((room) => (
                                <div key={room.id} className="border border-border rounded-lg p-3 text-sm">
                                    <p className="font-medium">{room.latest_booking?.guest_name ?? room.current_guest_name ?? 'Guest'}</p>
                                    <p className="text-xs text-muted-foreground">Room {room.room_number} • {room.room_type?.value ?? room.room_type ?? 'N/A'} • {room.status?.value ?? room.status}</p>
                                </div>
                            ))}
                        </div>
                    </section>
                )}

                {activeTab === 'tasks' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Tasks</h3>
                        {tasks.length === 0 ? <p className="text-sm text-muted-foreground">No tasks available.</p> : (
                            <div className="space-y-2">
                                {tasks.map((task) => (
                                    <div key={task.id} className="border border-border rounded-lg p-3 flex items-center justify-between gap-2">
                                        <div>
                                            <p className="font-medium text-sm">{task.title}</p>
                                            <p className="text-xs text-muted-foreground">{task.description}</p>
                                        </div>
                                        <span className="text-xs px-2 py-0.5 rounded-full bg-muted capitalize">{task.status?.value ?? task.status ?? 'pending'}</span>
                                    </div>
                                ))}
                            </div>
                        )}
                    </section>
                )}

                {activeTab === 'logs' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Activity Logs</h3>
                        {activityLogs.length === 0 ? <p className="text-sm text-muted-foreground">No logs yet.</p> : (
                            <div className="space-y-2 max-h-96 overflow-auto">
                                {activityLogs.map((log) => (
                                    <div key={log.id} className="border border-border rounded-lg p-3">
                                        <p className="text-sm">{log.action}</p>
                                        <p className="text-xs text-muted-foreground mt-1">{log.user_name ?? 'System'} • {new Date(log.created_at).toLocaleString()}</p>
                                    </div>
                                ))}
                            </div>
                        )}
                    </section>
                )}

                {activeTab === 'staff' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Staff Directory</h3>
                        {staff.length === 0 ? <p className="text-sm text-muted-foreground">No staff records found.</p> : (
                            <div className="grid sm:grid-cols-2 gap-3">
                                {staff.map((member) => (
                                    <div key={member.id} className="border border-border rounded-lg p-3">
                                        <p className="font-medium text-sm">{member.name}</p>
                                        <p className="text-xs text-muted-foreground capitalize">{member.role?.value ?? member.role}</p>
                                    </div>
                                ))}
                            </div>
                        )}
                    </section>
                )}

                {activeTab === 'setup' && (
                    <section className="bg-card border border-border rounded-2xl p-5 space-y-5">
                        <h3 className="font-serif text-xl">Hotel Setup</h3>
                        <div className="grid lg:grid-cols-3 gap-4">
                            <form className="border border-border rounded-xl p-3 space-y-2" onSubmit={async (event) => {
                                event.preventDefault();
                                await axios.post('/api/room-categories', {
                                    ...categoryForm,
                                    default_price: Number(categoryForm.default_price || 0),
                                });
                                setCategoryForm({ name: '', description: '', default_price: '' });
                                router.reload({ only: ['categories'] });
                            }}>
                                <p className="font-medium text-sm">Add Category</p>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Category name" value={categoryForm.name} onChange={(event) => setCategoryForm((prev) => ({ ...prev, name: event.target.value }))} required />
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Description" value={categoryForm.description} onChange={(event) => setCategoryForm((prev) => ({ ...prev, description: event.target.value }))} />
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" type="number" min="0" placeholder="Default price" value={categoryForm.default_price} onChange={(event) => setCategoryForm((prev) => ({ ...prev, default_price: event.target.value }))} />
                                <button className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Save Category</button>
                            </form>
                            <form className="border border-border rounded-xl p-3 space-y-2" onSubmit={async (event) => {
                                event.preventDefault();
                                await axios.post('/api/rooms', {
                                    ...roomForm,
                                    price_per_night: Number(roomForm.price_per_night || 0),
                                    status: 'available',
                                });
                                setRoomForm({ category_id: '', display_name: '', room_number: '', room_type: 'Single', price_per_night: '' });
                                router.reload({ only: ['rooms'] });
                            }}>
                                <p className="font-medium text-sm">Add Room</p>
                                <select className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background" value={roomForm.category_id} onChange={(event) => setRoomForm((prev) => ({ ...prev, category_id: event.target.value }))} required>
                                    <option value="">Select category</option>
                                    {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
                                </select>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Room name" value={roomForm.display_name} onChange={(event) => setRoomForm((prev) => ({ ...prev, display_name: event.target.value }))} required />
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Room number" value={roomForm.room_number} onChange={(event) => setRoomForm((prev) => ({ ...prev, room_number: event.target.value }))} required />
                                <select className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background" value={roomForm.room_type} onChange={(event) => setRoomForm((prev) => ({ ...prev, room_type: event.target.value }))}>
                                    <option value="Single">Single</option>
                                    <option value="Double">Double</option>
                                    <option value="Suite">Suite</option>
                                    <option value="Deluxe">Deluxe</option>
                                </select>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" type="number" min="0" placeholder="Price per night" value={roomForm.price_per_night} onChange={(event) => setRoomForm((prev) => ({ ...prev, price_per_night: event.target.value }))} required />
                                <button className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Save Room</button>
                            </form>
                            <form className="border border-border rounded-xl p-3 space-y-2" onSubmit={async (event) => {
                                event.preventDefault();
                                await axios.post('/api/staff', staffForm);
                                setStaffForm({ name: '', role: 'receptionist', username: '', password: '' });
                                router.reload({ only: ['staff'] });
                            }}>
                                <p className="font-medium text-sm">Create Staff</p>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Staff name" value={staffForm.name} onChange={(event) => setStaffForm((prev) => ({ ...prev, name: event.target.value }))} required />
                                <select className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background" value={staffForm.role} onChange={(event) => setStaffForm((prev) => ({ ...prev, role: event.target.value }))}>
                                    <option value="receptionist">Receptionist</option>
                                    <option value="maintenance">Maintenance</option>
                                    <option value="manager">Manager</option>
                                    <option value="janitor">Janitor</option>
                                </select>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="Staff username" value={staffForm.username} onChange={(event) => setStaffForm((prev) => ({ ...prev, username: event.target.value }))} required />
                                <div className="relative">
                                    <input className="w-full border border-border rounded-lg px-2 py-1 text-sm pr-9" type={showStaffPassword ? 'text' : 'password'} placeholder="Staff password" value={staffForm.password} onChange={(event) => setStaffForm((prev) => ({ ...prev, password: event.target.value }))} required />
                                    <button type="button" onClick={() => setShowStaffPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                                        {showStaffPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                                    </button>
                                </div>
                                <button className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Create Staff</button>
                            </form>
                            <form className="border border-border rounded-xl p-3 space-y-2" onSubmit={async (event) => {
                                event.preventDefault();
                                await axios.post('/admin/password/change', passwordForm);
                                setPasswordForm({ code: '', new_password: '', new_password_confirmation: '' });
                                alert('Password updated successfully.');
                            }}>
                                <p className="font-medium text-sm">Change Admin Password (SMS verified)</p>
                                <button
                                    type="button"
                                    className="w-full px-3 py-2 rounded-lg border border-border text-sm"
                                    onClick={async () => {
                                        await axios.post('/admin/password/send-code');
                                        alert('Verification code sent to hotel contact number.');
                                    }}
                                >
                                    Send verification code
                                </button>
                                <input className="w-full border border-border rounded-lg px-2 py-1 text-sm" placeholder="6-digit code" value={passwordForm.code} onChange={(event) => setPasswordForm((prev) => ({ ...prev, code: event.target.value }))} required />
                                <div className="relative">
                                    <input className="w-full border border-border rounded-lg px-2 py-1 text-sm pr-9" type={showAdminNewPassword ? 'text' : 'password'} placeholder="New password" value={passwordForm.new_password} onChange={(event) => setPasswordForm((prev) => ({ ...prev, new_password: event.target.value }))} required />
                                    <button type="button" onClick={() => setShowAdminNewPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                                        {showAdminNewPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                                    </button>
                                </div>
                                <div className="relative">
                                    <input className="w-full border border-border rounded-lg px-2 py-1 text-sm pr-9" type={showAdminConfirmPassword ? 'text' : 'password'} placeholder="Confirm new password" value={passwordForm.new_password_confirmation} onChange={(event) => setPasswordForm((prev) => ({ ...prev, new_password_confirmation: event.target.value }))} required />
                                    <button type="button" onClick={() => setShowAdminConfirmPassword((prev) => !prev)} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground">
                                        {showAdminConfirmPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                                    </button>
                                </div>
                                <button className="w-full px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm">Update Password</button>
                            </form>
                        </div>
                    </section>
                )}

                {activeTab === 'sos' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-2">SOS Alerts</h3>
                        <p className="text-sm text-muted-foreground">SOS module is active and ready for incoming alerts.</p>
                    </section>
                )}

                {activeTab === 'sales' && (
                    <section className="bg-card border border-border rounded-2xl p-5">
                        <h3 className="font-serif text-xl mb-3">Sales Reports</h3>
                        <div className="flex gap-2">
                            <button onClick={() => window.open('/api/reports/sales-pdf', '_blank')} className="px-3 py-2 rounded-full bg-primary text-primary-foreground text-sm">Open Sales PDF</button>
                            <button onClick={() => window.open('/api/reports/sales-csv', '_blank')} className="px-3 py-2 rounded-full bg-secondary text-sm">Export CSV</button>
                        </div>
                        <div className="mt-4 grid sm:grid-cols-2 lg:grid-cols-4 gap-2">
                            {salesSummary.map((period) => (
                                <div key={period.id} className="border border-border rounded-xl p-3">
                                    <p className="text-xs text-muted-foreground">{period.label}</p>
                                    <p className="text-lg font-semibold">{period.bookings} bookings</p>
                                    <p className="text-sm text-primary">PHP {period.amount.toLocaleString()}</p>
                                </div>
                            ))}
                        </div>
                        <div className="mt-4">
                            <SalesBars data={salesSummary} />
                        </div>
                        <div className="mt-4 text-sm text-muted-foreground space-y-1">
                            <p>External reservations: {reservations.length}</p>
                            <p>Checkout reminders scheduled: {reminders.length}</p>
                            <p>Post-stay reviews submitted: {reviews.length}</p>
                            <p>Room transfers: {transfers.length}</p>
                        </div>
                    </section>
                )}
            </div>
        </AdminLayout>
    );
}

function MetricCard({ label, value, onClick }) {
    return (
        <button type="button" onClick={onClick} className="text-left rounded-xl border border-border bg-card p-3 hover:border-primary transition-colors">
            <p className="text-xs text-muted-foreground">{label}</p>
            <p className="font-serif text-xl">{value}</p>
        </button>
    );
}

function SalesBars({ data = [] }) {
    const max = Math.max(1, ...data.map((item) => item.amount));
    return (
        <div className="border border-border rounded-2xl p-4 bg-background space-y-3">
            <p className="text-sm text-muted-foreground">Revenue chart (day/week/month/year)</p>
            {data.map((item) => (
                <div key={item.id} className="space-y-1">
                    <div className="flex items-center justify-between text-xs">
                        <span>{item.label}</span>
                        <span>PHP {item.amount.toLocaleString()}</span>
                    </div>
                    <div className="h-2 rounded-full bg-muted/40">
                        <div className="h-2 rounded-full bg-primary" style={{ width: `${Math.max(6, (item.amount / max) * 100)}%` }} />
                    </div>
                </div>
            ))}
        </div>
    );
}
