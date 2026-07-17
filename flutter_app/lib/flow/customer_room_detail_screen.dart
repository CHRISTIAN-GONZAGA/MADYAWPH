import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../locale_controller.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/chat_attachment.dart';
import 'admin/widgets/hourly_billing.dart';
import 'customer_booking_status_screen.dart';
import 'customer_search_context.dart';
import 'member_login_screen.dart';

/// Room detail + guest booking form for the public customer portal.
/// Submits via POST /customer/reservations (admin approval in Bookings tab).
class CustomerRoomDetailScreen extends StatefulWidget {
  const CustomerRoomDetailScreen({
    super.key,
    required this.hotelId,
    required this.hotelName,
    required this.room,
    required this.categoryName,
    this.categoryImageUrl = '',
    this.categoryDescription = '',
    this.searchContext,
    this.preferReserve = false,
  });

  final String hotelId;
  final String hotelName;
  final Map<String, dynamic> room;
  final String categoryName;
  final String categoryImageUrl;
  final String categoryDescription;
  final CustomerSearchContext? searchContext;
  final bool preferReserve;

  @override
  State<CustomerRoomDetailScreen> createState() =>
      _CustomerRoomDetailScreenState();
}

class _CustomerRoomDetailScreenState extends State<CustomerRoomDetailScreen> {
  final _pageCtrl = PageController();
  int _galleryPage = 0;
  bool _submitting = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _checkInCtrl;
  late final TextEditingController _checkOutCtrl;

  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  var _discountType = 'none';
  var _paymentMethod = 'Cash';
  XFile? _discountIdFile;
  XFile? _guestIdFile;
  String _paymentQrUrl = '';
  var _qrLoading = false;
  var _guestFieldsReady = false;
  var _adults = 2;
  var _children = 0;
  var _guestsMale = 0;
  var _guestsFemale = 0;
  var _memberLoggedIn = false;
  var _memberDiscountPercent = 0.0;
  String _memberDisplayName = '';
  String _memberShid = '';

  bool get _fromSearch => widget.searchContext != null;
  bool get _hasMemberDiscount =>
      _memberLoggedIn && _memberDiscountPercent > 0;

  @override
  void initState() {
    super.initState();
    _checkInDate = _fromSearch ? widget.searchContext!.checkIn : null;
    _checkOutDate = _fromSearch ? widget.searchContext!.checkOut : null;
    if (_fromSearch) {
      _adults = widget.searchContext!.adults;
      _children = widget.searchContext!.children;
    }
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _checkInCtrl = TextEditingController(
      text: _fromSearch ? widget.searchContext!.checkInIso : '',
    );
    _checkOutCtrl = TextEditingController(
      text: _fromSearch ? widget.searchContext!.checkOutIso : '',
    );
    _bootstrapForm();
  }

  Future<void> _bootstrapForm() async {
    final saved = await AuthStorage.customerGuestContact();
    if (!mounted) return;
    _nameCtrl.text = saved?.name ?? '';
    _emailCtrl.text = saved?.email ?? '';
    _phoneCtrl.text = saved?.phone ?? '';

    var loggedIn = false;
    var shid = '';
    var displayName = '';
    var percent = 0.0;

    final token = await AuthStorage.memberToken();
    if ((token ?? '').isNotEmpty) {
      try {
        final res =
            await memberDio().get<Map<String, dynamic>>('/member/dashboard');
        final member = res.data?['member'];
        if (member is Map) {
          final map = Map<String, dynamic>.from(member);
          await AuthStorage.setMemberProfile(
            shidId: (map['member_shid_id'] ?? '').toString(),
            fullName: (map['full_name'] ?? '').toString(),
            discountPercent:
                (map['member_discount_percent'] as num?)?.toDouble() ?? 0,
          );
          shid = (map['member_shid_id'] ?? '').toString().toUpperCase();
          displayName = (map['full_name'] ?? '').toString().trim();
          percent =
              (map['member_discount_percent'] as num?)?.toDouble() ?? 0;
          loggedIn = shid.isNotEmpty;
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await AuthStorage.clearMemberAuth();
        } else {
          // Offline / transient: fall back to cached profile if available.
          shid = ((await AuthStorage.memberShidId()) ?? '').toUpperCase();
          displayName = (await AuthStorage.memberFullName()) ?? '';
          percent = await AuthStorage.memberDiscountPercent();
          loggedIn = shid.isNotEmpty;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _guestFieldsReady = true;
      _memberLoggedIn = loggedIn;
      _memberShid = shid;
      _memberDisplayName = displayName;
      _memberDiscountPercent = loggedIn ? percent : 0;
      if (loggedIn && percent > 0) {
        _discountType = 'none';
        _discountIdFile = null;
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    super.dispose();
  }

  List<String> get _galleryUrls {
    final urls = <String>[];
    void add(String raw) {
      final resolved = ChatAttachment.resolveMediaUrl(raw);
      if (resolved.isNotEmpty && !urls.contains(resolved)) {
        urls.add(resolved);
      }
    }

    add('${widget.room['image_url'] ?? ''}');
    add(widget.categoryImageUrl);
    return urls;
  }

  List<String> get _amenities {
    final raw = widget.room['amenities'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _loadPaymentQr() async {
    setState(() => _qrLoading = true);
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/payment-qr',
        queryParameters: {'hotel_id': widget.hotelId},
      );
      _paymentQrUrl = (res.data?['qr_url'] ?? '').toString();
    } catch (_) {
      _paymentQrUrl = '';
    } finally {
      if (mounted) setState(() => _qrLoading = false);
    }
  }

  Future<void> _pickCheckIn() async {
    if (_fromSearch) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDate: _checkInDate ?? today,
    );
    if (picked == null) return;
    setState(() {
      _checkInDate = picked;
      _checkInCtrl.text = picked.toIso8601String().split('T').first;
      if (HourlyBilling.isHourly(widget.room)) {
        // Hourly stays are clock + block hours; checkout date matches check-in day.
        _checkOutDate = picked;
        _checkOutCtrl.text = picked.toIso8601String().split('T').first;
      } else if (_checkOutDate != null && !_checkOutDate!.isAfter(picked)) {
        _checkOutDate = null;
        _checkOutCtrl.clear();
      }
    });
  }

  Future<void> _pickCheckOut({required bool forceReserve}) async {
    if (_fromSearch) return;
    if (HourlyBilling.isHourly(widget.room)) {
      // Checkout is auto-calculated from check-in + block hours.
      return;
    }
    if (_checkInDate == null) {
      showAppMessage(context, context.tr('select_checkin_first'));
      return;
    }
    final picked = await showDatePicker(
      context: context,
      firstDate: _checkInDate!.add(const Duration(days: 1)),
      lastDate: _checkInDate!.add(const Duration(days: 365)),
      initialDate: _checkOutDate ?? _checkInDate!.add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _checkOutDate = picked;
      _checkOutCtrl.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> _submit({required bool reserve}) async {
    if (_submitting) return;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      showAppMessage(context, 'Enter your full name.');
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      showAppMessage(context, 'Enter a valid email address or leave it blank.');
      return;
    }
    if (phone.length < 7) {
      showAppMessage(context, 'Enter a valid phone number.');
      return;
    }
    if (_fromSearch && _guestIdFile == null) {
      showAppMessage(context, 'Upload your government ID.');
      return;
    }
    if (_discountType != 'none' && _discountIdFile == null) {
      showAppMessage(context, 'Upload a photo of your discount ID.');
      return;
    }
    if (_hasMemberDiscount && _discountType != 'none') {
      showAppMessage(
        context,
        'Member discount is already applied. Clear PWD/senior to continue.',
      );
      return;
    }
    if (_checkInCtrl.text.trim().isEmpty) {
      showAppMessage(context, 'Select check-in.');
      return;
    }
    if (HourlyBilling.isHourly(widget.room)) {
      final inDay = _checkInDate ?? DateTime.tryParse(_checkInCtrl.text.trim());
      if (inDay != null) {
        final day = DateTime(inDay.year, inDay.month, inDay.day);
        _checkInDate = day;
        _checkOutDate = day;
        _checkOutCtrl.text = day.toIso8601String().split('T').first;
      }
    }
    if (_checkOutCtrl.text.trim().isEmpty) {
      showAppMessage(context, 'Select check-in and check-out.');
      return;
    }

    final payload = <String, dynamic>{
      'room_id': (widget.room['id'] ?? '').toString(),
      'guest_name': name,
      'guest_phone': phone,
      'check_in': _checkInCtrl.text.trim(),
      'check_out': _checkOutCtrl.text.trim(),
      'discount_type': _hasMemberDiscount ? 'none' : _discountType,
      'payment_method': _paymentMethod,
      'hotel_id': widget.hotelId,
      'adults': _adults,
      'children': _children,
      'guests_male': _guestsMale,
      'guests_female': _guestsFemale,
    };
    if (email.isNotEmpty) payload['guest_email'] = email;
    if (widget.searchContext != null) {
      payload['rooms'] = widget.searchContext!.rooms;
    }

    setState(() => _submitting = true);
    try {
      await AuthStorage.setCustomerGuestContact(
        name: name,
        email: email,
        phone: phone,
      );

      const path = '/customer/reservations';
      final discount = _hasMemberDiscount ? 'none' : _discountType;
      final hasDiscountFile = discount != 'none' && _discountIdFile != null;
      final hasGuestId = _guestIdFile != null;
      final dio = customerBookingDio();

      final Response<Map<String, dynamic>> res;
      if (hasDiscountFile || hasGuestId) {
        final map = <String, dynamic>{};
        for (final entry in payload.entries) {
          final v = entry.value;
          if (v != null) {
            map[entry.key] = v is num || v is bool ? v.toString() : v;
          }
        }
        if (discount != 'none') map['discount_type'] = discount;
        if (hasGuestId) {
          map['guest_id_file'] = await MultipartFile.fromFile(
            _guestIdFile!.path,
            filename: _guestIdFile!.name.isNotEmpty
                ? _guestIdFile!.name
                : 'guest_id.jpg',
          );
        }
        if (hasDiscountFile) {
          map['discount_id_file'] = await MultipartFile.fromFile(
            _discountIdFile!.path,
            filename: _discountIdFile!.name.isNotEmpty
                ? _discountIdFile!.name
                : 'discount_id.jpg',
          );
        }
        res = await dio.post<Map<String, dynamic>>(
          path,
          data: FormData.fromMap(map),
        );
      } else {
        res = await dio.post<Map<String, dynamic>>(path, data: payload);
      }

      if (!mounted) return;
      final reservation = res.data?['reservation'] as Map<String, dynamic>?;

      if (reservation != null) {
        final ref = (reservation['external_reference'] ?? '').toString();
        if (ref.isEmpty) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => CustomerBookingStatusScreen(
              hotelId: widget.hotelId,
              hotelName: widget.hotelName,
              reference: ref,
              guestEmail: email,
              guestPhone: phone,
              initialReservation: Map<String, dynamic>.from(reservation),
            ),
          ),
          (route) => route.isFirst,
        );
        return;
      }

      showAppMessage(context, 'Request submitted. Awaiting hotel approval.');
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_guestFieldsReady) {
      return const AppScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final room = widget.room;
    final title = (room['display_name'] ?? room['room_number'] ?? 'Room')
        .toString();
    final roomNo = (room['room_number'] ?? '').toString();
    final priceLabel = HourlyBilling.priceLabel(room);
    final surge = room['base_price_per_night'] != null &&
        room['base_price_per_night'] != room['price_per_night'];
    final gallery = _galleryUrls;
    final nights = (_checkInDate != null && _checkOutDate != null)
        ? _checkOutDate!.difference(_checkInDate!).inDays
        : 0;
    final safeNights = nights > 0 ? nights : 0;
    final isHourly = HourlyBilling.isHourly(room);
    final hourlyWindow = (_checkInDate != null && isHourly)
        ? HourlyBilling.clockBasedStayWindow(room, _checkInDate!)
        : null;
    final estTotal = isHourly && hourlyWindow != null
        ? HourlyBilling.stayCharge(
            room,
            hourlyWindow.checkIn,
            hourlyWindow.checkOut,
          )
        : (_checkInDate != null && _checkOutDate != null)
            ? HourlyBilling.customerDateStayCharge(
                room,
                _checkInDate!,
                _checkOutDate!,
              )
            : 0.0;
    final discountPct = _memberDiscountPercent > 0
        ? _memberDiscountPercent
        : switch (_discountType) {
            'pwd' => 20.0,
            'senior' => 20.0,
            _ => 0.0,
          };
    final estAfterDiscount =
        HourlyBilling.round50(estTotal * (1 - (discountPct / 100)));
    String fmtTime(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    }
    final staySummary = isHourly && hourlyWindow != null
        ? '${HourlyBilling.blockHours(room)} hr stay · '
            'approx ${fmtTime(hourlyWindow.checkIn)} → ${fmtTime(hourlyWindow.checkOut)}'
        : (safeNights > 0
            ? '$safeNights night${safeNights == 1 ? '' : 's'}'
            : '');

    return LocaleScope(
      builder: (context, _) => AppScaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (gallery.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _pageCtrl,
                        itemCount: gallery.length,
                        onPageChanged: (i) => setState(() => _galleryPage = i),
                        itemBuilder: (context, i) => NetworkMediaImage(
                          url: gallery[i],
                          fit: BoxFit.cover,
                          error: ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.bed_outlined,
                              size: 48,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ),
                      if (gallery.length > 1)
                        Positioned(
                          bottom: 10,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(gallery.length, (i) {
                              final active = i == _galleryPage;
                              return Container(
                                width: active ? 18 : 7,
                                height: 7,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: active ? Colors.white : Colors.white54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Room $roomNo · ${widget.categoryName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(priceLabel),
                  backgroundColor: scheme.primaryContainer,
                ),
                if (surge) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('Demand pricing'),
                    backgroundColor: scheme.tertiaryContainer,
                  ),
                ],
              ],
            ),
            if (widget.categoryDescription.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                widget.categoryDescription.trim(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_amenities.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Room amenities',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _amenities
                    .map(
                      (a) => Chip(
                        label: Text(a),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              _fromSearch
                  ? context.tr('complete_booking')
                  : (widget.preferReserve
                      ? context.tr('request_reservation')
                      : context.tr('book_room_title')),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your request is sent to the hotel for approval. '
              'Front desk or admin confirms it in the Bookings section.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            if (_fromSearch && widget.searchContext != null) ...[
              Card(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'From your search',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.searchContext!.checkInIso} → ${widget.searchContext!.checkOutIso}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Guests in room',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            _GuestCounterRow(
              label: 'Adults',
              value: _adults,
              min: 1,
              onChanged: (v) => setState(() => _adults = v),
            ),
            _GuestCounterRow(
              label: 'Children',
              value: _children,
              onChanged: (v) => setState(() => _children = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Demographics (head count)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            _GuestCounterRow(
              label: 'Male',
              value: _guestsMale,
              onChanged: (v) => setState(() => _guestsMale = v),
            ),
            _GuestCounterRow(
              label: 'Female',
              value: _guestsFemale,
              onChanged: (v) => setState(() => _guestsFemale = v),
            ),
            const SizedBox(height: 12),
            AppInput(controller: _nameCtrl, label: context.tr('full_name')),
            const SizedBox(height: 8),
            AppInput(
              controller: _emailCtrl,
              label: '${context.tr('email_gmail')} (optional)',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            AppInput(
              controller: _phoneCtrl,
              label: context.tr('phone_number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            if (_memberLoggedIn) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _memberDisplayName.isNotEmpty
                          ? 'Signed in as $_memberDisplayName'
                          : 'MADYAWPH member signed in',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasMemberDiscount
                          ? '${_memberDiscountPercent.toStringAsFixed(0)}% member discount applies automatically — no membership ID needed.'
                          : 'Your membership is linked. Member rates apply when active on the platform.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    if (_memberShid.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _memberShid,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              Text(
                'MADYAWPH membership',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sign in as a member to apply your discount automatically. Guests cannot enter a membership ID here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MemberLoginScreen(
                        popOnSuccess: true,
                      ),
                    ),
                  );
                  if (mounted) await _bootstrapForm();
                },
                icon: const Icon(Icons.card_membership_outlined),
                label: const Text('Member sign in'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final file = await ChatAttachment.pick(context);
                if (file != null) setState(() => _guestIdFile = file);
              },
              icon: const Icon(Icons.credit_card_outlined),
              label: Text(
                _guestIdFile == null
                    ? (_fromSearch
                        ? 'Upload government ID *'
                        : 'Upload government ID (optional)')
                    : 'ID attached — tap to replace',
              ),
            ),
            if (!_hasMemberDiscount) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _discountType,
                decoration: const InputDecoration(
                  labelText: 'Discount (optional)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No discount')),
                  DropdownMenuItem(value: 'pwd', child: Text('PWD (20% off)')),
                  DropdownMenuItem(
                    value: 'senior',
                    child: Text('Senior citizen (20% off)'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _discountType = v ?? 'none';
                  if (_discountType == 'none') _discountIdFile = null;
                }),
              ),
              if (_discountType != 'none') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ChatAttachment.pick(context);
                    if (file != null) setState(() => _discountIdFile = file);
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(
                    _discountIdFile == null
                        ? 'Upload discount ID photo'
                        : 'Discount ID attached — tap to replace',
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'PWD / senior citizen options are hidden while your member rate is active.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            AppInput(
              controller: _checkInCtrl,
              label: _fromSearch ? 'Check-in' : 'Check-in date',
              hint: _fromSearch ? null : 'Tap to open calendar',
              readOnly: true,
              onTap: _fromSearch ? null : _pickCheckIn,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            const SizedBox(height: 8),
            if (isHourly && !_fromSearch) ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Check-out (auto)',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  hourlyWindow == null
                      ? 'Select check-in to see your stay end time'
                      : '${_checkOutCtrl.text} · approx ${fmtTime(hourlyWindow.checkOut)} '
                          '(${HourlyBilling.blockHours(room)} hr block)',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hourly rooms use your arrival time on the check-in day plus the room’s block length. The hotel confirms the exact window.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ] else
              AppInput(
                controller: _checkOutCtrl,
                label: 'Check-out date',
                hint: _fromSearch ? null : 'Tap to open calendar',
                readOnly: true,
                onTap: _fromSearch
                    ? null
                    : () => _pickCheckOut(
                          forceReserve: _fromSearch || widget.preferReserve,
                        ),
                suffixIcon: const Icon(Icons.calendar_month_outlined),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash at hotel')),
                DropdownMenuItem(value: 'Online', child: Text('Online (QR Ph)')),
              ],
              onChanged: (v) async {
                final next = v ?? 'Cash';
                setState(() => _paymentMethod = next);
                if (next == 'Online' && _paymentQrUrl.isEmpty) {
                  await _loadPaymentQr();
                }
              },
            ),
            if (_paymentMethod == 'Online') ...[
              const SizedBox(height: 12),
              if (_qrLoading)
                const Center(child: CircularProgressIndicator())
              else if (_paymentQrUrl.isEmpty)
                Text(
                  'Hotel has not uploaded a payment QR yet. You can still submit a request and pay at the desk.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                )
              else
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Scan to pay via GCash / Maya / QR Ph',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      NetworkMediaImage(
                        url: _paymentQrUrl,
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'After paying, keep your reference ready. The hotel confirms your request before the stay is active.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              [
                if (staySummary.isNotEmpty) 'Duration: $staySummary',
                'Estimated: ₱${estTotal.toStringAsFixed(2)}'
                    '${discountPct > 0 ? ' → ₱${estAfterDiscount.toStringAsFixed(2)} after discount' : ''}',
                'Hotel approval required before your stay is confirmed.',
              ].join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (_fromSearch)
              AppPrimaryButton(
                label: _submitting ? 'Submitting…' : 'Submit booking request',
                onPressed: _submitting ? null : () => _submit(reserve: true),
              )
            else
              AppPrimaryButton(
                label: _submitting
                    ? 'Submitting…'
                    : (widget.preferReserve
                        ? 'Request reservation'
                        : 'Request to book'),
                onPressed: _submitting
                    ? null
                    : () => _submit(reserve: widget.preferReserve),
              ),
            if (!_fromSearch) ...[
              const SizedBox(height: 8),
              Text(
                'Your request goes to the front desk for approval. You will get room access details once they confirm.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuestCounterRow extends StatelessWidget {
  const _GuestCounterRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// Opens the public customer room detail + booking form.
Future<bool?> openCustomerRoomDetail(
  BuildContext context, {
  required String hotelId,
  required String hotelName,
  required Map<String, dynamic> room,
  required String categoryName,
  String categoryImageUrl = '',
  String categoryDescription = '',
  CustomerSearchContext? searchContext,
  bool preferReserve = false,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => CustomerRoomDetailScreen(
        hotelId: hotelId,
        hotelName: hotelName,
        room: room,
        categoryName: categoryName,
        categoryImageUrl: categoryImageUrl,
        categoryDescription: categoryDescription,
        searchContext: searchContext,
        preferReserve: preferReserve,
      ),
    ),
  );
}
