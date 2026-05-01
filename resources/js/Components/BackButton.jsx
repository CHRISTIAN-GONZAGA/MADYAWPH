import { router } from '@inertiajs/react';
import { ArrowLeft } from 'lucide-react';

export default function BackButton({ fallback = '/login', className = '' }) {
    const goBack = () => {
        if (typeof window !== 'undefined' && window.history.length > 1) {
            window.history.back();
            return;
        }

        router.visit(fallback);
    };

    return (
        <button
            type="button"
            onClick={goBack}
            className={`inline-flex min-h-[44px] items-center gap-2 rounded-full border border-border bg-card px-4 py-2 text-sm font-semibold text-muted-foreground transition hover:border-primary/40 hover:text-foreground ${className}`}
        >
            <ArrowLeft className="h-4 w-4" />
            Back
        </button>
    );
}
