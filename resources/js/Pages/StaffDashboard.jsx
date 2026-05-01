import { Link } from '@inertiajs/react';
import { ClipboardList, User } from 'lucide-react';
import { useState } from 'react';
import AppLayout from '../Layouts/AppLayout';
import Badge from '../Components/Badge';
import Card from '../Components/Card';

const tabs = ['Tasks', 'Rooms', 'Orders'];

export default function StaffDashboard() {
    const [tab, setTab] = useState('Tasks');

    return (
        <AppLayout title="Staff dashboard" subtitle="Maintenance · John Martinez">
            <div className="mb-6 flex gap-2 overflow-x-auto rounded-full bg-card p-1 shadow-card">
                {tabs.map((t) =>
                    t === 'Rooms' ? (
                        <Link
                            key={t}
                            href="/rooms"
                            className="flex min-h-[44px] flex-1 items-center justify-center rounded-full px-4 py-2 text-sm font-semibold text-muted-foreground transition hover:bg-primary/10 hover:text-foreground"
                        >
                            {t}
                        </Link>
                    ) : (
                        <button
                            key={t}
                            type="button"
                            onClick={() => setTab(t)}
                            className={`min-h-[44px] flex-1 rounded-full px-4 py-2 text-sm font-semibold transition ${
                                tab === t ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
                            }`}
                        >
                            {t}
                        </button>
                    ),
                )}
            </div>

            <section className="mb-6">
                <h2 className="mb-3 font-serif text-lg font-semibold text-foreground">My tasks</h2>
                <div className="space-y-4">
                    <Card interactive className="border-l-4 border-l-destructive">
                        <div className="flex items-start justify-between gap-2">
                            <div>
                                <Badge variant="pending">High</Badge>
                                <p className="mt-2 font-medium text-foreground">Fix AC in room 104</p>
                                <p className="text-sm text-muted-foreground">Deadline: Today, 2:00 PM</p>
                            </div>
                            <ClipboardList className="h-5 w-5 shrink-0 text-muted-foreground" />
                        </div>
                        <select className="mt-4 w-full rounded-xl border border-border bg-background py-2 text-sm">
                            <option>Pending</option>
                            <option>In progress</option>
                            <option>Done</option>
                        </select>
                    </Card>
                    <Card interactive>
                        <Badge variant="neutral">Med</Badge>
                        <p className="mt-2 font-medium text-foreground">Clean pool area</p>
                        <p className="text-sm text-muted-foreground">Deadline: Apr 14</p>
                        <select className="mt-4 w-full rounded-xl border border-border bg-background py-2 text-sm">
                            <option>In progress</option>
                            <option>Pending</option>
                            <option>Done</option>
                        </select>
                    </Card>
                </div>
            </section>

            <Card className="border-accent/30 bg-gradient-to-br from-card to-accent/5">
                <div className="flex items-center gap-2">
                    <User className="h-5 w-5 text-primary" />
                    <p className="font-medium text-foreground">Performance</p>
                </div>
                <p className="mt-2 font-serif text-2xl font-bold text-primary">92%</p>
                <p className="text-sm text-muted-foreground">45 tasks completed this month</p>
            </Card>
        </AppLayout>
    );
}
