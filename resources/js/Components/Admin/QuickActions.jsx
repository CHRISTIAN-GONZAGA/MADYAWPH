import { motion } from 'motion/react';
import { CreditCard, BedDouble, Bell, ClipboardList, MessageCircle, ShieldAlert } from 'lucide-react';

const actions = [
    { id: 'overview', label: 'Manage Rooms', icon: BedDouble },
    { id: 'credits', label: 'Credits', icon: CreditCard },
    { id: 'tasks', label: 'Tasks', icon: ClipboardList },
    { id: 'chat', label: 'Guest Chat', icon: MessageCircle },
    { id: 'sos', label: 'SOS Alerts', icon: ShieldAlert },
    { id: 'logs', label: 'Logs', icon: Bell },
];

export default function QuickActions({ onNavigate, pendingTasksCount = 0 }) {
    return (
        <section>
            <h2 className="text-xl font-serif mb-4">Quick Actions</h2>
            <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
                {actions.map((action) => (
                    <motion.button
                        key={action.id}
                        whileHover={{ y: -2 }}
                        whileTap={{ scale: 0.98 }}
                        onClick={() => onNavigate?.(action.id)}
                        className="bg-card border border-border rounded-xl p-4 text-left"
                    >
                        <action.icon className="w-5 h-5 text-primary mb-2" />
                        <p className="font-medium">{action.label}</p>
                        {action.id === 'tasks' && (
                            <p className="text-xs text-muted-foreground mt-1">{pendingTasksCount} pending tasks</p>
                        )}
                    </motion.button>
                ))}
            </div>
        </section>
    );
}
