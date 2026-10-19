import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lentera3/app.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('splash 3 detik lalu Mode Dasar tanpa menumpuk halaman',
      (tester) async {
    final h = Harness(window: const Duration(seconds: 30));
    await tester.pumpWidget(LenteraApp(controller: h.controller));

    expect(find.text('Layanan Informasi Harian Ramah Akses bagi Tunanetra'),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 2, milliseconds: 900));
    expect(find.text('Mode Dasar'), findsNothing); // belum 3 detik

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mode Dasar'), findsOneWidget);
    expect(find.text('Selamat Datang di Lentera'), findsOneWidget);
    expect(find.text('Sedang mendengarkan...'), findsOneWidget);

    // Bongkar pohon widget: controller.dispose() membatalkan semua Timer.
    await tester.pumpWidget(const SizedBox());
  });
}
