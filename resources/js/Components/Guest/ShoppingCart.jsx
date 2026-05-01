export default function ShoppingCart({ items = [] }) {
    if (!items.length) return null;
    return (
        <div className="bg-card border border-border rounded-2xl p-4 shadow-sm">
            <h3 className="font-serif text-lg mb-3">Request Summary</h3>
            <div className="space-y-2 text-sm">
                {items.map((item) => (
                    <div key={item.type} className="flex justify-between bg-background rounded-lg px-3 py-2 border border-border/60">
                        <span>{item.name}</span>
                        <span>x{item.quantity}</span>
                    </div>
                ))}
            </div>
        </div>
    );
}
