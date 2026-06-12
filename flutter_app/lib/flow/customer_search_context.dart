/// Search criteria from the public hotel landing screen, passed through booking.
class CustomerSearchContext {
  const CustomerSearchContext({
    required this.checkIn,
    required this.checkOut,
    this.rooms = 1,
    this.adults = 2,
    this.children = 0,
    this.destinationQuery = '',
  });

  final DateTime checkIn;
  final DateTime checkOut;
  final int rooms;
  final int adults;
  final int children;
  final String destinationQuery;

  String get checkInIso => _dateOnly(checkIn);
  String get checkOutIso => _dateOnly(checkOut);

  Map<String, String> get queryParams => {
        'check_in': checkInIso,
        'check_out': checkOutIso,
        'rooms': '$rooms',
        'adults': '$adults',
        'children': '$children',
      };

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
