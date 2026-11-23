import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/screens/notifications_screen.dart';
import 'package:supra_mobile_ui/widgets/notification_tile.dart';

AppNotification item(
  String id,
  NotificationSeverity severity, {
  bool news = true,
}) => AppNotification(
  id: id,
  userId: 'test',
  title: id,
  messageBody: 'Publisher report',
  severity: severity,
  sentAt: DateTime.now(),
  isRead: false,
  sourceUrl: news ? 'https://www.antaranews.com/berita/test' : null,
);
void main() {
  final items = [
    item('low-news', NotificationSeverity.low),
    item('medium-news', NotificationSeverity.moderate),
    item('high-news', NotificationSeverity.high),
    item('critical-news', NotificationSeverity.critical),
    item('weather-alert', NotificationSeverity.low, news: false),
  ];
  testWidgets('Inbox filters and alerts scroll together on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: (_) async => [
            for (var i = 1; i <= 12; i++)
              item('Peringatan $i', NotificationSeverity.moderate, news: false),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = find.byKey(const ValueKey('alerts-page-scroll'));
    final scrollable = find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first;
    final last = find.text('Peringatan 12');
    await tester.scrollUntilVisible(last, 260, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(find.text('Tandai semua sudah dibaca').hitTestable(), findsNothing);
    expect(find.text('Sedang').hitTestable(), findsWidgets);
    expect(find.textContaining('severity'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('News minimum ordering leaves weather alerts independent and persists in JSON', () {
    expect(items.where((n) => n.meetsNewsMinimum('medium')).map((n) => n.id), [
      'medium-news',
      'high-news',
      'critical-news',
      'weather-alert',
    ]);
    expect(items.where((n) => n.meetsNewsMinimum('high')).map((n) => n.id), [
      'high-news',
      'critical-news',
      'weather-alert',
    ]);
    final pref = const NotificationPreference(alertRelevantNews: false)
        .copyWith(newsMinSeverity: 'high');
    final read = NotificationPreference.fromJson(pref.toJson());
    expect(read.newsMinSeverity, 'high');
    expect(read.alertRelevantNews, false);
  });
  test('Existing alert visibility follows individual saved flags', () {
    final rain = AppNotification.fromJson({
      'id': 'rain',
      'user_id': 'test',
      'title': 'Hujan',
      'message_body': 'Hujan',
      'severity': 'medium',
      'sent_at': DateTime.now().toIso8601String(),
      'is_read': false,
      'context': {'rule': 'rain'},
    });
    expect(
      const NotificationPreference(alertHeavyRain: false)
          .allowsNotification(rain),
      false,
    );
    expect(
      const NotificationPreference(alertRelevantNews: false)
          .allowsNotification(items.first),
      false,
    );
    expect(
      const NotificationPreference(newsMinSeverity: 'high')
          .allowsNotification(items.first),
      false,
    );
    expect(
      const NotificationPreference(newsMinSeverity: 'high')
          .allowsNotification(rain),
      true,
    );
  });

  testWidgets(
    'Profile preference changes hide existing low news before a reload completes',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = ValueNotifier(const NotificationPreference());
      addTearDown(preferences.dispose);
      final pending = Completer<List<AppNotification>>();
      var calls = 0;
      final requested = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            preferenceChanges: preferences,
            loadNotifications: (minimum) {
              requested.add(minimum);
              return calls++ == 0 ? Future.value(items) : pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('low-news'), findsOneWidget);
      preferences.value = const NotificationPreference(
        newsMinSeverity: 'medium',
      );
      await tester.pump();
      expect(find.text('low-news'), findsNothing);
      expect(find.text('medium-news'), findsOneWidget);
      expect(find.text('Sedang atau lebih tinggi'), findsOneWidget);
      expect(find.text('Berita (3)'), findsOneWidget);
      expect(requested, ['low', 'medium']);
      pending.complete(items);
      await tester.pumpAndSettle();
      expect(find.text('low-news'), findsNothing);
      preferences.value = const NotificationPreference(
        alertRelevantNews: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('high-news'), findsNothing);
      expect(find.text('weather-alert'), findsOneWidget);
    },
  );

  testWidgets(
    'Delete read removes read news and alerts, preserving unread items',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = [
        item('read-news', NotificationSeverity.high).copyWith(isRead: true),
        item(
          'read-weather',
          NotificationSeverity.low,
          news: false,
        ).copyWith(isRead: true),
        item('unread-news', NotificationSeverity.high),
      ];
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            loadNotifications: (_) async =>
                List<AppNotification>.unmodifiable(backend),
            deleteReadAlerts: () async {
              calls++;
              final count = backend.where((n) => n.isRead).length;
              backend.removeWhere((n) => n.isRead);
              return count;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus yang sudah dibaca'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Unsupported operation'), findsNothing);
      expect(
        find.textContaining('Peringatan yang sudah dibaca gagal dihapus'),
        findsNothing,
      );
      expect(find.text('read-news'), findsNothing);
      expect(find.text('read-weather'), findsNothing);
      expect(find.text('unread-news'), findsOneWidget);
      expect(
        find.text('2 peringatan yang sudah dibaca dihapus.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hapus yang sudah dibaca'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tidak ada peringatan yang sudah dibaca untuk dihapus.'),
        findsOneWidget,
      );
      expect(find.text('unread-news'), findsOneWidget);
    },
  );

  testWidgets('Visible bulk buttons and individual unread work on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var backend = [
      item(
        'selected-alert',
        NotificationSeverity.high,
        news: false,
      ).copyWith(isRead: true),
    ];
    var markAll = 0;
    final toggled = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: (_) async =>
              List<AppNotification>.unmodifiable(backend),
          setReadState: (id, read) async {
            toggled.add(read);
            backend = backend
                .map((n) => n.id == id ? n.copyWith(isRead: read) : n)
                .toList();
          },
          markAllReadAlerts: () async {
            markAll++;
            backend = backend.map((n) => n.copyWith(isRead: true)).toList();
            return backend.length;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tandai semua sudah dibaca'), findsOneWidget);
    expect(find.text('Hapus yang sudah dibaca'), findsOneWidget);
    expect(find.byTooltip('Manage alerts'), findsNothing);
    await tester.tap(find.text('Tandai belum dibaca'));
    await tester.pumpAndSettle();
    expect(toggled, [false]);
    expect(
      tester
          .widget<NotificationTile>(find.byType(NotificationTile))
          .notification
          .isRead,
      false,
    );
    await tester.tap(find.text('Tandai semua sudah dibaca'));
    await tester.pumpAndSettle();
    expect(markAll, 1);
    expect(
      tester
          .widget<NotificationTile>(find.byType(NotificationTile))
          .notification
          .isRead,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Checkbox selection marks only chosen read alerts unread', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var backend = [
      for (final id in ['one', 'two', 'three'])
        item(id, NotificationSeverity.high, news: false).copyWith(isRead: true),
    ];
    final batches = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: (_) async =>
              List<AppNotification>.unmodifiable(backend),
          markSelectedUnread: (ids) async {
            batches.add(ids);
            backend = backend
                .map((n) => ids.contains(n.id) ? n.copyWith(isRead: false) : n)
                .toList();
            return ids.length;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(0));
    await tester.pumpAndSettle();
    await tester.tap(boxes.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tandai pilihan belum dibaca'));
    await tester.pumpAndSettle();
    expect(batches.single, ['one', 'two']);
    final displayed = tester
        .widgetList<NotificationTile>(find.byType(NotificationTile))
        .map((t) => t.notification)
        .toList();
    expect(displayed.map((n) => n.isRead), [false, false, true]);
    expect(find.text('Tandai pilihan belum dibaca'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Failed selected unread keeps read state and selection for retry',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            loadNotifications: (_) async => [
              item(
                'one',
                NotificationSeverity.high,
                news: false,
              ).copyWith(isRead: true),
            ],
            markSelectedUnread: (_) async => throw StateError('offline'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tandai pilihan belum dibaca'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .notification
            .isRead,
        true,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
      expect(
        find.textContaining('Gagal menandai pilihan belum dibaca'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Failed delete leaves read alerts visible for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: (_) async => [
            item('read-news', NotificationSeverity.high).copyWith(isRead: true),
          ],
          deleteReadAlerts: () async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus yang sudah dibaca'));
    await tester.pumpAndSettle();
    expect(find.text('read-news'), findsOneWidget);
    expect(
      find.textContaining('Peringatan yang sudah dibaca gagal dihapus'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Inbox saves Medium+ and High+ filters and retains non-news alerts',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            initialPreferences: const NotificationPreference(),
            loadNotifications: (_) async => items,
            saveNewsSeverity: (value) async {
              saved.add(value);
              return NotificationPreference(newsMinSeverity: value);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationTile), findsNWidgets(5));
      await tester.tap(find.text('Semua tingkat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sedang atau lebih tinggi').last);
      await tester.pumpAndSettle();
      expect(saved, ['medium']);
      expect(find.text('low-news'), findsNothing);
      expect(find.text('weather-alert'), findsOneWidget);
      await tester.tap(find.text('Sedang atau lebih tinggi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tinggi atau lebih tinggi').last);
      await tester.pumpAndSettle();
      expect(saved, ['medium', 'high']);
      expect(find.text('medium-news'), findsNothing);
      expect(find.text('high-news'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Failed preference save rolls the news filter back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: (_) async => items,
          saveNewsSeverity: (_) async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua tingkat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tinggi atau lebih tinggi').last);
    await tester.pumpAndSettle();
    expect(find.text('Semua tingkat'), findsOneWidget);
    expect(find.textContaining('Filter berita gagal disimpan'), findsOneWidget);
  });
}
