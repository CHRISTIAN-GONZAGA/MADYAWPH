export default function Input({ label, error, className = '', id, ...props }) {
    const inputId = id ?? props.name;
    return (
        <div className="w-full">
            {label && (
                <label htmlFor={inputId} className="mb-1 block text-sm font-medium text-foreground">
                    {label}
                </label>
            )}
            <input
                id={inputId}
                className={`w-full border-0 border-b-2 border-border bg-transparent py-3 text-base text-foreground placeholder:text-muted outline-none transition focus:border-primary ${error ? 'border-destructive' : ''} ${className}`}
                {...props}
            />
            {error && <p className="mt-1 text-sm text-destructive">{error}</p>}
        </div>
    );
}
