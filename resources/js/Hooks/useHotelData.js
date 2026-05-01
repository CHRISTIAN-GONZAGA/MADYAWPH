import { useMemo } from 'react';

export default function useHotelData(data = []) {
    return useMemo(() => {
        return {
            total: data.length,
            active: data.filter((item) => item?.status !== 'inactive').length,
            items: data,
        };
    }, [data]);
}
