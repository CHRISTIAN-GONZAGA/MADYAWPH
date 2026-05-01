export default function AmenityCard({ amenity, quantity, onDecrement, onIncrement, onRequest, disabled }) {
    return (
        <div className="bg-card border border-border rounded-2xl p-4 shadow-sm hover:shadow-md transition-all">
            <div className="flex items-center justify-between mb-2">
                <p className="text-2xl">{amenity.icon}</p>
                {disabled && <span className="text-xs bg-amber-100 text-amber-700 px-2 py-1 rounded-full">Pending</span>}
            </div>
            <h4 className="font-serif text-lg">{amenity.name}</h4>
            <p className="text-sm text-muted-foreground mb-4">{amenity.description}</p>
            <div className="flex items-center gap-2">
                <button type="button" onClick={onDecrement} className="px-2 py-1 border border-border rounded-full w-8 h-8">-</button>
                <span className="w-8 text-center">{quantity}</span>
                <button type="button" onClick={onIncrement} className="px-2 py-1 border border-border rounded-full w-8 h-8">+</button>
                <button
                    type="button"
                    onClick={onRequest}
                    disabled={disabled}
                    className="ml-auto px-4 py-2 bg-primary text-primary-foreground rounded-full text-sm disabled:opacity-50"
                >
                    Request
                </button>
            </div>
        </div>
    );
}
