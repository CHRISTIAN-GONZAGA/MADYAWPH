export default function AuthLayout({ title = 'MADYAW', subtitle, children }) {
    return (
        <div className="min-h-screen bg-background text-foreground relative">
            <div className="absolute inset-0 opacity-10 pointer-events-none bg-linen" />
            <div className="relative z-10 min-h-screen flex flex-col items-center justify-center px-4 py-10">
                <div className="text-center mb-8">
                    <h1 className="font-serif text-4xl sm:text-5xl">{title}</h1>
                    {subtitle && <p className="text-muted-foreground mt-2">{subtitle}</p>}
                </div>
                <div className="w-full max-w-md bg-card border border-border rounded-2xl shadow-card p-6 sm:p-8">
                    {children}
                </div>
            </div>
        </div>
    );
}
