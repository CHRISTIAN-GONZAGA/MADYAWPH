import './bootstrap';
import '../css/app.css';
import { createInertiaApp, router } from '@inertiajs/react';
import { createRoot } from 'react-dom/client';
import { applyStoredThemeColor } from './Utils/theme';

applyStoredThemeColor();

// Fallback to a full-page navigation when an intermediate proxy/cache
// strips Inertia response headers and the client marks a response invalid.
router.on('invalid', (event) => {
    event.preventDefault();

    const fallbackUrl = event?.detail?.response?.request?.responseURL || window.location.href;
    window.location.assign(fallbackUrl);
});

createInertiaApp({
    resolve: (name) => {
        const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true });
        return pages[`./Pages/${name}.jsx`];
    },
    setup({ el, App, props }) {
        createRoot(el).render(<App {...props} />);
    },
});
