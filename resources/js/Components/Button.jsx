const variants = {
    primary:
        'bg-primary text-primary-foreground shadow-card hover:opacity-95 active:scale-[0.98] disabled:opacity-50',
    secondary:
        'border border-primary bg-transparent text-primary hover:bg-card active:scale-[0.98] disabled:opacity-50',
    destructive:
        'bg-destructive text-white shadow-card hover:opacity-95 active:scale-[0.98] disabled:opacity-50',
    ghost: 'text-primary hover:bg-card active:scale-[0.98]',
};

export default function Button({ variant = 'primary', className = '', type = 'button', children, ...props }) {
    return (
        <button
            type={type}
            className={`inline-flex min-h-11 min-w-[44px] items-center justify-center rounded-full px-6 py-3 text-base font-medium transition duration-200 ${variants[variant]} ${className}`}
            {...props}
        >
            {children}
        </button>
    );
}
