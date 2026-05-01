export default function StatCard({ label, value, trend, accent = 'primary' }) {
    const accents = {
        primary: 'from-primary/15 to-accent/10',
        green: 'from-status-available-bg to-emerald-100/50',
        red: 'from-status-booked-bg to-red-100/40',
        amber: 'from-status-maintenance-bg to-amber-100/40',
    };

    return (
        <div
            className={`rounded-2xl border border-border bg-gradient-to-br ${accents[accent]} p-5 shadow-card transition hover:shadow-md`}
        >
            <p className="text-sm font-medium text-muted-foreground">{label}</p>
            <p className="mt-1 font-serif text-3xl font-bold tracking-tight text-foreground">{value}</p>
            {trend && <p className="mt-2 text-xs font-medium text-success">{trend}</p>}
        </div>
    );
}
