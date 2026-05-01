export default function Card({ interactive, className = '', children, ...props }) {
    return (
        <div
            className={`rounded-2xl border border-border bg-card p-5 shadow-card ${interactive ? 'transition duration-200 hover:-translate-y-1 hover:shadow-md active:scale-[0.98]' : ''} ${className}`}
            {...props}
        >
            {children}
        </div>
    );
}
