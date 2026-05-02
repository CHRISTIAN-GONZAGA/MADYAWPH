import axios from 'axios';
import { http } from '@inertiajs/core';

/**
 * Inertia shows a modal + iframe for non-Inertia HTML responses. Prevent that and
 * use a normal browser navigation instead (avoids the "small window" overlay).
 */
if (typeof document !== 'undefined') {
    document.addEventListener(
        'inertia:httpException',
        (event) => {
            event.preventDefault();
            const response = event.detail?.response;
            const headers = response?.headers ?? {};
            const headerGet = (name) => {
                const lower = name.toLowerCase();
                const key = Object.keys(headers).find((k) => k.toLowerCase() === lower);
                return key ? headers[key] : undefined;
            };
            // 409 external redirects use X-Inertia-Location, not Location — reloading would loop on /auth/hotel.
            const loc = headerGet('location') ?? headerGet('x-inertia-location');
            if (typeof loc === 'string' && loc.length > 0) {
                window.location.assign(loc);
            } else {
                window.location.reload();
            }
        },
        true,
    );
}

window.axios = axios;

window.axios.defaults.headers.common['X-Requested-With'] = 'XMLHttpRequest';
window.axios.defaults.withCredentials = true;
window.axios.defaults.xsrfCookieName = 'XSRF-TOKEN';
window.axios.defaults.xsrfHeaderName = 'X-XSRF-TOKEN';

/**
 * When the browser treats the request as cross-origin, custom response headers like
 * X-Inertia are hidden unless Access-Control-Expose-Headers lists them. Inertia's
 * XHR client then sees no x-inertia header and throws "plain JSON response".
 * If the body is clearly an Inertia page payload, mark it as a valid Inertia response.
 */
function looksLikeInertiaPage(data) {
    return (
        data !== null &&
        typeof data === 'object' &&
        typeof data.component === 'string' &&
        'props' in data &&
        typeof data.url === 'string'
    );
}

http.onResponse((response) => {
    if (!response.headers) {
        response.headers = {};
    }
    const { headers } = response;
    if (headers['x-inertia']) {
        return response;
    }

    let parsed = response.data;
    if (typeof parsed === 'string') {
        try {
            parsed = JSON.parse(parsed);
        } catch {
            return response;
        }
    }

    if (looksLikeInertiaPage(parsed)) {
        headers['x-inertia'] = 'true';
    }

    return response;
});
