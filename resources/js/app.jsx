import './bootstrap';
import '../css/app.css';
import { createInertiaApp } from '@inertiajs/react';
import { createRoot } from 'react-dom/client';
import { applyStoredThemeColor } from './Utils/theme';

applyStoredThemeColor();

createInertiaApp({
    resolve: (name) => {
        const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true });
        return pages[`./Pages/${name}.jsx`];
    },
    setup({ el, App, props }) {
        createRoot(el).render(<App {...props} />);
    },
    // Avoid Inertia's built-in error modal (iframe dialog); use a normal full-page navigation instead.
    defaults: {
        visitOptions: (href, options) => ({
            ...options,
            onHttpException: (response) => {
                const prev = options.onHttpException?.(response);
                if (prev === false) {
                    return false;
                }
                const headers = response.headers ?? {};
                const location =
                    headers.location ??
                    headers.Location ??
                    headers['location'];
                if (typeof location === 'string' && location !== '') {
                    window.location.assign(location);
                    return false;
                }
                window.location.reload();
                return false;
            },
        }),
    },
});
