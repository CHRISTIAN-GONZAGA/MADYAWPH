const styles = {
    available: 'bg-status-available-bg text-emerald-800 ring-1 ring-emerald-200/60',
    booked: 'bg-status-booked-bg text-red-800 ring-1 ring-red-200/60',
    maintenance: 'bg-status-maintenance-bg text-amber-900 ring-1 ring-amber-200/60',
    pending: 'bg-status-pending-bg text-amber-900 ring-1 ring-amber-200/60',
    fulfilled: 'bg-status-fulfilled-bg text-emerald-900 ring-1 ring-emerald-200/60',
    neutral: 'bg-card text-muted-foreground ring-1 ring-border',
};

export default function Badge({ variant = 'neutral', className = '', children }) {
    return (
        <span
            className={`inline-flex items-center rounded-full px-3 py-1 text-[11px] font-semibold uppercase tracking-wide ${styles[variant]} ${className}`}
        >
            {children}
        </span>
    );
}
