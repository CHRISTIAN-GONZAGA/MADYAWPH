import { useEffect, useMemo, useState } from 'react';
import axios from 'axios';
import AppLayout from '../Layouts/AppLayout';
import Badge from '../Components/Badge';
import Card from '../Components/Card';

const statusVariant = {
    available: 'available',
    booked: 'booked',
    maintenance: 'maintenance',
};

export default function RoomManagement() {
    const [rooms, setRooms] = useState([]);
    const [loading, setLoading] = useState(true);
    const [selectedFilter, setSelectedFilter] = useState('all');
    const [updatingRoomId, setUpdatingRoomId] = useState(null);

    useEffect(() => {
        const fetchRooms = async () => {
            setLoading(true);
            try {
                const params = selectedFilter === 'all' ? {} : { status: selectedFilter };
                const response = await axios.get('/api/rooms', { params });
                setRooms(response.data?.data ?? []);
            } finally {
                setLoading(false);
            }
        };

        fetchRooms();
    }, [selectedFilter]);

    const filterButtons = useMemo(
        () => [
            { key: 'all', label: 'All' },
            { key: 'available', label: 'Available' },
            { key: 'booked', label: 'Booked' },
            { key: 'maintenance', label: 'Maintenance' },
        ],
        [],
    );

    const cardTint = (status) => {
        if (status === 'available') return 'bg-status-available-bg/80 border-emerald-200/60';
        if (status === 'booked') return 'bg-status-booked-bg/80 border-red-200/50';
        if (status === 'maintenance') return 'bg-status-maintenance-bg/80 border-amber-200/50';
        return 'bg-card';
    };

    const updateRoomStatus = async (roomId, status) => {
        setUpdatingRoomId(roomId);
        try {
            await axios.put(`/api/rooms/${roomId}/status`, { status });
            setRooms((prev) => prev.map((room) => (room.id === roomId ? { ...room, status } : room)));
        } finally {
            setUpdatingRoomId(null);
        }
    };

    return (
        <AppLayout title="Room management" subtitle="Live status by room">
            <div className="mb-6 flex flex-wrap gap-2">
                {filterButtons.map((button) => (
                    <button
                        key={button.key}
                        type="button"
                        onClick={() => setSelectedFilter(button.key)}
                        className={`min-h-[44px] rounded-full border px-4 py-2 text-sm font-semibold transition ${
                            selectedFilter === button.key
                                ? 'border-primary bg-primary text-primary-foreground shadow-card'
                                : 'border-border bg-card text-muted-foreground hover:border-primary/40'
                        }`}
                    >
                        {button.label}
                    </button>
                ))}
            </div>

            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {loading && <p className="text-muted-foreground">Loading rooms…</p>}
                {!loading && rooms.length === 0 && <p className="text-muted-foreground">No rooms for this filter.</p>}
                {rooms.map((room) => {
                    const st = String(room.status ?? '').toLowerCase();
                    return (
                    <Card
                        key={room.id}
                        interactive
                        className={`border-2 ${cardTint(st)}`}
                    >
                        <div className="flex items-start justify-between gap-2">
                            <div>
                                <p className="font-serif text-2xl font-bold text-foreground">Room {room.room_number}</p>
                                <p className="text-sm text-muted-foreground">WiFi, TV, AC</p>
                            </div>
                            <Badge variant={statusVariant[st] ?? 'neutral'}>{room.status}</Badge>
                        </div>
                        <select
                            className="mt-4 w-full rounded-xl border border-border bg-background/80 py-2 text-sm font-medium capitalize disabled:opacity-60"
                            value={st}
                            disabled={updatingRoomId === room.id}
                            onChange={(e) => updateRoomStatus(room.id, e.target.value)}
                        >
                            <option value="available">available</option>
                            <option value="booked">booked</option>
                            <option value="maintenance">maintenance</option>
                        </select>
                    </Card>
                    );
                })}
            </div>
        </AppLayout>
    );
}
