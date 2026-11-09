import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/saved_trip.dart';
import 'package:supra_mobile_ui/models/trip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = TripHistoryStore.instance;
  const origin = LatLng(latitude: -6.2, longitude: 106.8);
  const destination = LatLng(latitude: -6.3, longitude: 106.9);
  Trip event(
    String id, {
    String user = 'alice',
    bool confirmed = true,
    LatLng? dest = destination,
    DateTime? at,
  }) => Trip(
    id: id,
    userId: user,
    name: 'Commute',
    startLocation: 'School',
    destination: 'Station',
    plannedDeparture: DateTime.utc(2030),
    confirmedAt: confirmed ? at ?? DateTime.utc(2026, 1, 1) : null,
    startPoint: origin,
    destPoint: dest,
  );
  setUp(() {
    store.resetForTesting();
    store.bindUser('alice');
  });
  test('No demo trips or ambiguous legacy cache are imported', () async {
    SharedPreferences.setMockInitialValues({
      'supra_saved_trips_v1': '[{"destination":"SMAN 67"}]',
    });
    expect(store.trips, isEmpty);
    store.syncWithServiceTrips([]);
    expect(store.trips, isEmpty);
  });
  test(
    'Groups confirmed events with actual coordinates and server timestamps',
    () {
      final newer = DateTime.utc(2026, 5, 1);
      store.syncWithServiceTrips([
        event('one'),
        event('two', at: newer),
        event('two', at: newer),
      ]);
      final trip = store.trips.single;
      expect(trip.id, 'two');
      expect(trip.frequency, 2);
      expect(trip.eventIds, ['two', 'one']);
      expect(trip.lastUsed, newer);
      expect(trip.startPoint, origin);
      expect(trip.destPoint, destination);
      expect(trip.toTrip().destPoint, destination);
      expect(trip.timeAgo, isNot('Just now'));
    },
  );
  test('Planned, incomplete, and other-user trips are not journey history', () {
    store.syncWithServiceTrips([
      event('planned', confirmed: false),
      event('missing', dest: null),
      event('bob', user: 'bob'),
    ]);
    expect(store.trips, isEmpty);
  });
  test('Repeated sync cannot reset frequency or reintroduce deleted backend events', () {
    final events = [event('one'), event('two')];
    store.syncWithServiceTrips(events);
    store.syncWithServiceTrips(events);
    expect(store.totalTripCount, 2);
    store.syncWithServiceTrips([events.first]);
    expect(store.totalTripCount, 1);
    store.syncWithServiceTrips([]);
    expect(store.trips, isEmpty);
  });
  test('Same-name destinations with different coordinates stay distinct', () {
    store.syncWithServiceTrips([event('one'), event('two', dest: origin)]);
    expect(store.trips.length, 2);
  });
  test('Account switching and logout clear projection immediately', () {
    store.syncWithServiceTrips([event('one')]);
    store.bindUser('bob');
    expect(store.trips, isEmpty);
    store.syncWithServiceTrips([event('one')]);
    expect(store.trips, isEmpty);
    store.bindUser(null);
    expect(store.trips, isEmpty);
  });
}
