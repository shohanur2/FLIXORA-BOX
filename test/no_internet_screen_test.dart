import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  testWidgets('No Internet screen shows the reference offline guidance',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NoInternetScreen(),
      ),
    );

    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('Connect to the internet'), findsOneWidget);
    expect(
      find.text('When your internet connection is restored:'),
      findsOneWidget,
    );
    expect(
      find.text('Explore various movies, TV series and more'),
      findsOneWidget,
    );
    expect(
      find.text('All free download with less data but good quality'),
      findsOneWidget,
    );
    expect(find.text('Watch offline without ads'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Go to Settings'), findsOneWidget);
  });
}
