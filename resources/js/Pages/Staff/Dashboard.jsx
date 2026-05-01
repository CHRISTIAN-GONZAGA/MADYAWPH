import { Head } from '@inertiajs/react';
import { motion } from 'motion/react';
import axios from 'axios';
import { useState } from 'react';
import { MessageCircle, BedDouble, ClipboardList } from 'lucide-react';
import BackButton from '../../Components/BackButton';
import StaffLayout from '../../Layouts/StaffLayout';

export default function Dashboard({ auth, tasks = [], guestMessages = [], rooms = [] }) {
    const [taskItems, setTaskItems] = useState(tasks);
    const [savingTaskId, setSavingTaskId] = useState(null);
    const [activeTab, setActiveTab] = useState('tasks');
    const unreadMessages = guestMessages.filter((message) => !message.is_read).length;
    const [reportRoomId, setReportRoomId] = useState('');
    const [reportNote, setReportNote] = useState('');
    const [reportImageFile, setReportImageFile] = useState(null);

    async function updateTaskStatus(taskId, status) {
        setSavingTaskId(taskId);
        try {
            await axios.put(`/api/tasks/${taskId}/status`, { status });
            setTaskItems((prev) => prev.map((task) => (task.id === taskId ? { ...task, status } : task)));
        } catch (_error) {
            alert('Unable to update task status.');
        } finally {
            setSavingTaskId(null);
        }
    }

    return (
        <StaffLayout user={auth?.user}>
            <Head title="Staff Dashboard" />
            <div className="space-y-5">
                <BackButton fallback="/staff/dashboard" />
                <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="rounded-2xl border border-border bg-card p-5">
                    <h2 className="font-serif text-2xl">Staff Dashboard</h2>
                    <p className="text-sm text-muted-foreground mt-1">Manage assigned tasks and update progress in real time.</p>
                </motion.div>
                <div className="flex gap-2 overflow-x-auto pb-1">
                    {[
                        { id: 'tasks', label: 'Tasks', icon: ClipboardList },
                        { id: 'chat', label: `Guest Chats${unreadMessages ? ` (${unreadMessages})` : ''}`, icon: MessageCircle },
                        { id: 'rooms', label: 'Room Status', icon: BedDouble },
                    ].map((tab) => (
                        <button
                            key={tab.id}
                            type="button"
                            onClick={() => setActiveTab(tab.id)}
                            className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap ${activeTab === tab.id ? 'bg-primary text-primary-foreground' : 'bg-card border border-border text-muted-foreground'}`}
                        >
                            {tab.label}
                        </button>
                    ))}
                </div>

                {activeTab === 'tasks' && (
                    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.08 }} className="bg-card border border-border rounded-2xl p-4">
                        <p className="text-sm text-muted-foreground mb-3">Assigned Tasks</p>
                        {taskItems.length === 0 ? <p className="text-sm">No pending tasks.</p> : (
                            <div className="space-y-3">
                                {taskItems.map((task) => {
                                    const currentStatus = task.status?.value ?? task.status ?? 'pending';
                                    return (
                                        <div key={task.id} className="rounded-xl border border-border bg-background p-3">
                                            <div className="flex items-start justify-between gap-2">
                                                <div>
                                                    <p className="font-medium">{task.title}</p>
                                                    <p className="text-xs text-muted-foreground">{task.description}</p>
                                                </div>
                                                <span className="text-[11px] uppercase tracking-wide px-2 py-0.5 rounded-full bg-muted">{currentStatus}</span>
                                            </div>
                                            <div className="mt-3 flex gap-2 flex-wrap">
                                                <button
                                                    type="button"
                                                    disabled={savingTaskId === task.id}
                                                    onClick={() => updateTaskStatus(task.id, 'pending')}
                                                    className="px-3 py-1.5 text-xs rounded-full border border-border hover:border-primary"
                                                >
                                                    Mark Pending
                                                </button>
                                                <button
                                                    type="button"
                                                    disabled={savingTaskId === task.id}
                                                    onClick={() => updateTaskStatus(task.id, 'in-progress')}
                                                    className="px-3 py-1.5 text-xs rounded-full border border-border hover:border-primary"
                                                >
                                                    In Progress
                                                </button>
                                                <button
                                                    type="button"
                                                    disabled={savingTaskId === task.id}
                                                    onClick={() => updateTaskStatus(task.id, 'completed')}
                                                    className="px-3 py-1.5 text-xs rounded-full bg-primary text-primary-foreground"
                                                >
                                                    Complete
                                                </button>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        )}
                    </motion.div>
                )}

                {activeTab === 'chat' && (
                    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="bg-card border border-border rounded-2xl p-4">
                        <p className="text-sm text-muted-foreground mb-3">Guest Chats</p>
                        {guestMessages.length === 0 ? <p className="text-sm">No guest chats yet.</p> : (
                            <div className="space-y-2 max-h-96 overflow-auto">
                                {guestMessages.map((message) => (
                                    <div key={message.id} className="rounded-xl border border-border bg-background p-3">
                                        <p className="text-sm">{message.message}</p>
                                        {message.attachment_url && <img src={message.attachment_url} alt="attachment" className="mt-2 rounded-lg max-h-40 w-auto" />}
                                        <p className="text-xs text-muted-foreground mt-1">Room {message.room_number ?? '-'} • {message.guest_name ?? 'Guest'}</p>
                                    </div>
                                ))}
                            </div>
                        )}
                        <div className="mt-4 border-t border-border pt-4 space-y-2">
                            <p className="text-sm font-medium">Report Maintenance Completion to Admin</p>
                            <select value={reportRoomId} onChange={(event) => setReportRoomId(event.target.value)} className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background">
                                <option value="">Select room</option>
                                {rooms.map((room) => <option key={room.id} value={room.id}>{room.room_number}</option>)}
                            </select>
                            <input value={reportNote} onChange={(event) => setReportNote(event.target.value)} className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background" placeholder="Maintenance update message" />
                            <input type="file" accept="image/*" capture="environment" onChange={(event) => setReportImageFile(event.target.files?.[0] ?? null)} className="w-full border border-border rounded-lg px-2 py-1 text-sm bg-background" />
                            <button
                                type="button"
                                className="px-3 py-2 text-xs rounded-lg bg-primary text-primary-foreground"
                                onClick={async () => {
                                    const room = rooms.find((item) => item.id === reportRoomId);
                                    if (!room || !reportNote.trim()) return;
                                    const form = new FormData();
                                    form.append('room_id', room.id);
                                    form.append('room_number', room.room_number);
                                    form.append('message', reportNote.trim());
                                    if (reportImageFile) form.append('image_file', reportImageFile);
                                    await axios.post('/staff/report-maintenance', form, { headers: { 'Content-Type': 'multipart/form-data' } });
                                    setReportNote('');
                                    setReportImageFile(null);
                                    alert('Maintenance report sent to admin.');
                                }}
                            >
                                Send to Admin
                            </button>
                        </div>
                    </motion.div>
                )}

                {activeTab === 'rooms' && (
                    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="bg-card border border-border rounded-2xl p-4">
                        <p className="text-sm text-muted-foreground mb-3">Room Status Snapshot</p>
                        <div className="grid sm:grid-cols-2 gap-2">
                            {rooms.slice(0, 20).map((room) => (
                                <div key={room.id} className="rounded-xl border border-border bg-background p-3 flex items-center justify-between">
                                    <p className="text-sm font-medium">Room {room.room_number}</p>
                                    <span className={`text-[11px] px-2 py-0.5 rounded-full capitalize ${
                                        (room.status?.value ?? room.status) === 'available'
                                            ? 'bg-emerald-100 text-emerald-700'
                                            : (room.status?.value ?? room.status) === 'booked'
                                                ? 'bg-red-100 text-red-700'
                                                : 'bg-amber-100 text-amber-700'
                                    }`}>
                                        {room.status?.value ?? room.status}
                                    </span>
                                </div>
                            ))}
                        </div>
                    </motion.div>
                )}
            </div>
        </StaffLayout>
    );
}
