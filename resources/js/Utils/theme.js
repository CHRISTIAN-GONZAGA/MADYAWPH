const DEFAULT_THEME = '#2563eb';

function clamp(value) {
    return Math.max(0, Math.min(255, Math.round(value)));
}

function hexToRgb(hex) {
    const clean = (hex ?? DEFAULT_THEME).replace('#', '');
    const normalized = clean.length === 6 ? clean : DEFAULT_THEME.replace('#', '');
    return {
        r: Number.parseInt(normalized.slice(0, 2), 16),
        g: Number.parseInt(normalized.slice(2, 4), 16),
        b: Number.parseInt(normalized.slice(4, 6), 16),
    };
}

function toHex({ r, g, b }) {
    return `#${clamp(r).toString(16).padStart(2, '0')}${clamp(g).toString(16).padStart(2, '0')}${clamp(b).toString(16).padStart(2, '0')}`;
}

function mix(color, target, weight) {
    return {
        r: color.r + ((target.r - color.r) * weight),
        g: color.g + ((target.g - color.g) * weight),
        b: color.b + ((target.b - color.b) * weight),
    };
}

export function applyThemeColor(color) {
    const root = document.documentElement;
    const rgb = hexToRgb(color);
    const dark = { r: 25, g: 30, b: 42 };
    const light = { r: 255, g: 255, b: 255 };

    const background = toHex(mix(rgb, light, 0.93));
    const card = toHex(mix(rgb, light, 0.88));
    const border = toHex(mix(rgb, light, 0.74));
    const muted = toHex(mix(rgb, light, 0.45));
    const foreground = toHex(mix(rgb, dark, 0.78));
    const mutedForeground = toHex(mix(rgb, dark, 0.52));
    const accent = toHex(mix(rgb, light, 0.22));

    root.style.setProperty('--color-primary', toHex(rgb));
    root.style.setProperty('--color-accent', accent);
    root.style.setProperty('--color-background', background);
    root.style.setProperty('--color-card', card);
    root.style.setProperty('--color-border', border);
    root.style.setProperty('--color-muted', muted);
    root.style.setProperty('--color-foreground', foreground);
    root.style.setProperty('--color-muted-foreground', mutedForeground);

    localStorage.setItem('app_theme_color', toHex(rgb));
}

export function applyStoredThemeColor() {
    const color = localStorage.getItem('app_theme_color');
    if (!color || !/^#([A-Fa-f0-9]{6})$/.test(color)) return;
    applyThemeColor(color);
}

