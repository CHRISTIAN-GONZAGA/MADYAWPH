export function formatCurrency(value, currency = 'PHP', locale = 'en-PH') {
    const numeric = Number(value ?? 0);
    if (Number.isNaN(numeric)) return '₱0';
    return new Intl.NumberFormat(locale, {
        style: 'currency',
        currency,
        maximumFractionDigits: 0,
    }).format(numeric);
}

export function formatDateTime(value, locale = 'en-PH') {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleString(locale);
}
