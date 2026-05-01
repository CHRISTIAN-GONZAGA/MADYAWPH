export function isPositiveNumber(value) {
    const numeric = Number(value);
    return Number.isFinite(numeric) && numeric > 0;
}

export function isPercentage(value) {
    const numeric = Number(value);
    return Number.isFinite(numeric) && numeric >= 0 && numeric <= 100;
}
