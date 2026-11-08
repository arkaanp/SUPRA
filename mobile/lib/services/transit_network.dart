import 'dart:math';

import '../models/location.dart';

enum TransitSystem {
  transjakarta('Transjakarta BRT', '🚌'),
  krl('KRL Commuter Line', '🚃'),
  mrt('MRT Jakarta', '🚆'),
  lrt('LRT Jabodebek', '🚊');

  final String displayName;
  final String icon;
  const TransitSystem(this.displayName, this.icon);
}

class TransitStation {
  final String id;
  final String name;
  final TransitSystem system;
  final String line;
  final LatLng point;
  final int sequenceIndex;

  const TransitStation({
    required this.id,
    required this.name,
    required this.system,
    required this.line,
    required this.point,
    required this.sequenceIndex,
  });
}

class TransitRouteResult {
  final TransitStation departureStation;
  final TransitStation arrivalStation;
  final List<TransitStation> intermediateStations;
  final List<LatLng> transitWaypoints;
  final List<String> turnSteps;
  final double walkToStationKm;
  final double railDistanceKm;
  final double walkFromStationKm;
  final Duration estimatedDuration;

  double get totalDistanceKm =>
      walkToStationKm + railDistanceKm + walkFromStationKm;

  const TransitRouteResult({
    required this.departureStation,
    required this.arrivalStation,
    required this.intermediateStations,
    required this.transitWaypoints,
    required this.turnSteps,
    required this.walkToStationKm,
    required this.railDistanceKm,
    required this.walkFromStationKm,
    required this.estimatedDuration,
  });
}

/// Official public transit network for Greater Jakarta covering Transjakarta BRT,
/// KRL Commuter Line, MRT Jakarta, and LRT Jabodebek.
abstract final class TransitNetwork {
  static const List<TransitStation> stations = [
    // =========================================================================
    // 1. TRANSJAKARTA BRT (Bus Rapid Transit with Dedicated Busway Corridors)
    // =========================================================================

    // --- Koridor 1: Blok M – Kota ---
    TransitStation(
      id: 'tj_blok_m',
      name: 'Halte Transjakarta Blok M',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2435, longitude: 106.7985),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'tj_csw_asean',
      name: 'Halte Transjakarta CSW / ASEAN',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2392, longitude: 106.7992),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'tj_masjid_agung',
      name: 'Halte Transjakarta Masjid Agung',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2325, longitude: 106.8005),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'tj_bundaran_senayan',
      name: 'Halte Transjakarta Bundaran Senayan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2268, longitude: 106.8020),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'tj_gbk',
      name: 'Halte Transjakarta Gelora Bung Karno',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2185, longitude: 106.8025),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'tj_polda_metro',
      name: 'Halte Transjakarta Polda Metro Jaya',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2235, longitude: 106.8095),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'tj_benhil',
      name: 'Halte Transjakarta Bendungan Hilir',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2162, longitude: 106.8185),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'tj_karet_sudirman',
      name: 'Halte Transjakarta Karet Sudirman',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2095, longitude: 106.8202),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'tj_dukuh_atas_1',
      name: 'Halte Transjakarta Dukuh Atas',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.2025, longitude: 106.8210),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'tj_tosari',
      name: 'Halte Transjakarta Tosari ICBC',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1985, longitude: 106.8222),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'tj_bundaran_hi',
      name: 'Halte Transjakarta Bundaran HI Astra',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1945, longitude: 106.8230),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'tj_thamrin',
      name: 'Halte Transjakarta M.H. Thamrin (Sarinah)',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1885, longitude: 106.8238),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'tj_bank_indonesia',
      name: 'Halte Transjakarta Bank Indonesia',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1822, longitude: 106.8235),
      sequenceIndex: 12,
    ),
    TransitStation(
      id: 'tj_monas',
      name: 'Halte Transjakarta Monumen Nasional (Monas)',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1765, longitude: 106.8232),
      sequenceIndex: 13,
    ),
    TransitStation(
      id: 'tj_harmoni',
      name: 'Halte Transjakarta Harmoni Central',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1668, longitude: 106.8198),
      sequenceIndex: 14,
    ),
    TransitStation(
      id: 'tj_sawah_besar',
      name: 'Halte Transjakarta Sawah Besar',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1585, longitude: 106.8192),
      sequenceIndex: 15,
    ),
    TransitStation(
      id: 'tj_mangga_besar',
      name: 'Halte Transjakarta Mangga Besar',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1502, longitude: 106.8185),
      sequenceIndex: 16,
    ),
    TransitStation(
      id: 'tj_glodok',
      name: 'Halte Transjakarta Glodok',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1435, longitude: 106.8142),
      sequenceIndex: 17,
    ),
    TransitStation(
      id: 'tj_kota',
      name: 'Halte Transjakarta Jakarta Kota',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 1',
      point: LatLng(latitude: -6.1378, longitude: 106.8145),
      sequenceIndex: 18,
    ),

    // --- Koridor 6: Ragunan – Mampang – Dukuh Atas 2 ---
    TransitStation(
      id: 'tj_ragunan',
      name: 'Halte Transjakarta Ragunan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.3120, longitude: 106.8205),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'tj_deptan',
      name: 'Halte Transjakarta Dept. Pertanian',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2970, longitude: 106.8245),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'tj_smk57',
      name: 'Halte Transjakarta SMK 57',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2875, longitude: 106.8265),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'tj_jatipadang',
      name: 'Halte Transjakarta Jati Padang',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2815, longitude: 106.8275),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'tj_pejaten',
      name: 'Halte Transjakarta Pejaten',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2735, longitude: 106.8285),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'tj_buncit',
      name: 'Halte Transjakarta Buncit Indah',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2650, longitude: 106.8290),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'tj_warung_jati',
      name: 'Halte Transjakarta Warung Jati',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2580, longitude: 106.8295),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'tj_imigrasi',
      name: 'Halte Transjakarta Imigrasi Jakarta Selatan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2510, longitude: 106.8300),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'tj_duren_tiga',
      name: 'Halte Transjakarta Duren Tiga',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2440, longitude: 106.8305),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'tj_mampang',
      name: 'Halte Transjakarta Mampang Prapatan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2370, longitude: 106.8310),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'tj_kuningan_barat',
      name: 'Halte Transjakarta Kuningan Barat',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2320, longitude: 106.8315),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'tj_patra',
      name: 'Halte Transjakarta Patra Kuningan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2260, longitude: 106.8320),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'tj_depkes',
      name: 'Halte Transjakarta Depkes Kuningan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2210, longitude: 106.8322),
      sequenceIndex: 12,
    ),
    TransitStation(
      id: 'tj_sumantri',
      name: 'Halte Transjakarta GOR Sumantri (Plaza Festival)',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2160, longitude: 106.8325),
      sequenceIndex: 13,
    ),
    TransitStation(
      id: 'tj_karet_kuningan',
      name: 'Halte Transjakarta Karet Kuningan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2120, longitude: 106.8328),
      sequenceIndex: 14,
    ),
    TransitStation(
      id: 'tj_kuningan_madya',
      name: 'Halte Transjakarta Kuningan Madya',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2080, longitude: 106.8330),
      sequenceIndex: 15,
    ),
    TransitStation(
      id: 'tj_setiabudi_utara',
      name: 'Halte Transjakarta Setiabudi Utara Aini',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2040, longitude: 106.8328),
      sequenceIndex: 16,
    ),
    TransitStation(
      id: 'tj_halimun',
      name: 'Halte Transjakarta Halimun',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2015, longitude: 106.8310),
      sequenceIndex: 17,
    ),
    TransitStation(
      id: 'tj_dukuh_atas_2',
      name: 'Halte Transjakarta Dukuh Atas 2',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 6',
      point: LatLng(latitude: -6.2025, longitude: 106.8220),
      sequenceIndex: 18,
    ),

    // --- Koridor 13: Ciledug – Velbak – CSW – Tendean ---
    TransitStation(
      id: 'tj_puri_beta',
      name: 'Halte Transjakarta Puri Beta 2 (Ciledug)',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2320, longitude: 106.7320),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'tj_petukangan',
      name: 'Halte Transjakarta Petukangan Selatan',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2345, longitude: 106.7550),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'tj_cipulir',
      name: 'Halte Transjakarta Cipulir',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2370, longitude: 106.7720),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'tj_kebayoran_lama',
      name: 'Halte Transjakarta Kebayoran Lama',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2385, longitude: 106.7820),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'tj_velbak',
      name: 'Halte Transjakarta Velbak',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2390, longitude: 106.7870),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'tj_mayestik',
      name: 'Halte Transjakarta Mayestik',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2405, longitude: 106.7920),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'tj_csw_13',
      name: 'Halte Transjakarta CSW (Koridor 13)',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2392, longitude: 106.7992),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'tj_tendean',
      name: 'Halte Transjakarta Kapten Tendean',
      system: TransitSystem.transjakarta,
      line: 'Transjakarta Koridor 13',
      point: LatLng(latitude: -6.2415, longitude: 106.8330),
      sequenceIndex: 7,
    ),

    // =========================================================================
    // 2. KRL COMMUTER LINE (Greater Jakarta Heavy Rail Commuter Network)
    // =========================================================================

    // --- KRL Bogor – Jakarta Kota Line ---
    TransitStation(
      id: 'krl_bogor',
      name: 'Stasiun KRL Bogor',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.5944, longitude: 106.7904),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'krl_cilebut',
      name: 'Stasiun KRL Cilebut',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.5285, longitude: 106.8010),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'krl_bojong_gede',
      name: 'Stasiun KRL Bojong Gede',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.4930, longitude: 106.7955),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'krl_citayam',
      name: 'Stasiun KRL Citayam',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.4485, longitude: 106.8015),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'krl_depok',
      name: 'Stasiun KRL Depok',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.4055, longitude: 106.8185),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'krl_depok_baru',
      name: 'Stasiun KRL Depok Baru',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3917, longitude: 106.8193),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'krl_pondok_cina',
      name: 'Stasiun KRL Pondok Cina',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3685, longitude: 106.8315),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'krl_ui',
      name: 'Stasiun KRL Universitas Indonesia',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3607, longitude: 106.8317),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'krl_up',
      name: 'Stasiun KRL Universitas Pancasila',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3385, longitude: 106.8340),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'krl_lenteng_agung',
      name: 'Stasiun KRL Lenteng Agung',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3305, longitude: 106.8350),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'krl_tanjung_barat',
      name: 'Stasiun KRL Tanjung Barat',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3075, longitude: 106.8390),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'krl_pasar_minggu',
      name: 'Stasiun KRL Pasar Minggu',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2842, longitude: 106.8443),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'krl_pasar_minggu_baru',
      name: 'Stasiun KRL Pasar Minggu Baru',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2635, longitude: 106.8525),
      sequenceIndex: 12,
    ),
    TransitStation(
      id: 'krl_kalibata',
      name: 'Stasiun KRL Duren Kalibata',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2555, longitude: 106.8550),
      sequenceIndex: 13,
    ),
    TransitStation(
      id: 'krl_cawang',
      name: 'Stasiun KRL Cawang',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2425, longitude: 106.8587),
      sequenceIndex: 14,
    ),
    TransitStation(
      id: 'krl_tebet',
      name: 'Stasiun KRL Tebet',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2263, longitude: 106.8582),
      sequenceIndex: 15,
    ),
    TransitStation(
      id: 'krl_manggarai',
      name: 'Stasiun KRL Manggarai Central',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2099, longitude: 106.8499),
      sequenceIndex: 16,
    ),
    TransitStation(
      id: 'krl_cikini',
      name: 'Stasiun KRL Cikini',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1983, longitude: 106.8427),
      sequenceIndex: 17,
    ),
    TransitStation(
      id: 'krl_gondangdia',
      name: 'Stasiun KRL Gondangdia (Monas Selatan)',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1863, longitude: 106.8329),
      sequenceIndex: 18,
    ),
    TransitStation(
      id: 'krl_juanda',
      name: 'Stasiun KRL Juanda (Monas Utara)',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1668, longitude: 106.8282),
      sequenceIndex: 19,
    ),
    TransitStation(
      id: 'krl_sawah_besar',
      name: 'Stasiun KRL Sawah Besar',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1605, longitude: 106.8250),
      sequenceIndex: 20,
    ),
    TransitStation(
      id: 'krl_mangga_besar',
      name: 'Stasiun KRL Mangga Besar',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1495, longitude: 106.8240),
      sequenceIndex: 21,
    ),
    TransitStation(
      id: 'krl_jayakarta',
      name: 'Stasiun KRL Jayakarta',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1415, longitude: 106.8230),
      sequenceIndex: 22,
    ),
    TransitStation(
      id: 'krl_jakarta_kota',
      name: 'Stasiun KRL Jakarta Kota',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1376, longitude: 106.8146),
      sequenceIndex: 23,
    ),

    // --- KRL Cikarang – Bekasi – Sudirman Loop Line ---
    TransitStation(
      id: 'krl_cikarang',
      name: 'Stasiun KRL Cikarang',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2550, longitude: 107.1510),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'krl_tambun',
      name: 'Stasiun KRL Tambun',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2605, longitude: 107.0600),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'krl_bekasi_timur',
      name: 'Stasiun KRL Bekasi Timur',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2490, longitude: 107.0180),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'krl_bekasi',
      name: 'Stasiun KRL Bekasi',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2365, longitude: 106.9995),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'krl_kranji',
      name: 'Stasiun KRL Kranji',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2245, longitude: 106.9790),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'krl_cakung',
      name: 'Stasiun KRL Cakung',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2195, longitude: 106.9530),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'krl_klender',
      name: 'Stasiun KRL Klender',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2135, longitude: 106.8990),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'krl_jatinegara',
      name: 'Stasiun KRL Jatinegara',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2150, longitude: 106.8680),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'krl_sudirman',
      name: 'Stasiun KRL Sudirman (Dukuh Atas)',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2023, longitude: 106.8236),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'krl_karet',
      name: 'Stasiun KRL Karet',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2010, longitude: 106.8170),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'krl_tanah_abang_loop',
      name: 'Stasiun KRL Tanah Abang',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.1857, longitude: 106.8110),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'krl_duri',
      name: 'Stasiun KRL Duri',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.1555, longitude: 106.8010),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'krl_kampung_bandan',
      name: 'Stasiun KRL Kampung Bandan',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.1325, longitude: 106.8250),
      sequenceIndex: 12,
    ),
    TransitStation(
      id: 'krl_pasar_senen',
      name: 'Stasiun KRL Pasar Senen',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.1745, longitude: 106.8440),
      sequenceIndex: 13,
    ),

    // --- KRL Serpong / Rangkasbitung Line ---
    TransitStation(
      id: 'krl_serpong',
      name: 'Stasiun KRL Serpong',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.3210, longitude: 106.6660),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'krl_rawa_buntu',
      name: 'Stasiun KRL Rawa Buntu',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.3025, longitude: 106.6850),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'krl_sudimara',
      name: 'Stasiun KRL Sudimara',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.2950, longitude: 106.7110),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'krl_jurang_mangu',
      name: 'Stasiun KRL Jurang Mangu',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.2890, longitude: 106.7320),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'krl_pondok_ranji',
      name: 'Stasiun KRL Pondok Ranji',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.2760, longitude: 106.7450),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'krl_kebayoran',
      name: 'Stasiun KRL Kebayoran (Gandaria)',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.2372, longitude: 106.7828),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'krl_palmerah',
      name: 'Stasiun KRL Palmerah (DPR/MPR)',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.2070, longitude: 106.7970),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'krl_tanah_abang_serpong',
      name: 'Stasiun KRL Tanah Abang',
      system: TransitSystem.krl,
      line: 'KRL Serpong Line',
      point: LatLng(latitude: -6.1857, longitude: 106.8110),
      sequenceIndex: 7,
    ),

    // =========================================================================
    // 3. MRT JAKARTA (North-South Rapid Transit Line)
    // =========================================================================
    TransitStation(
      id: 'mrt_lebak_bulus',
      name: 'Stasiun MRT Lebak Bulus Grab',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2894, longitude: 106.7745),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'mrt_fatmawati',
      name: 'Stasiun MRT Fatmawati',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2926, longitude: 106.7937),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'mrt_cipete',
      name: 'Stasiun MRT Cipete Raya',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2778, longitude: 106.7972),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'mrt_haji_nawi',
      name: 'Stasiun MRT Haji Nawi',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2662, longitude: 106.7976),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'mrt_blok_a',
      name: 'Stasiun MRT Blok A',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2554, longitude: 106.7974),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'mrt_blok_m',
      name: 'Stasiun MRT Blok M BCA',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2445, longitude: 106.7981),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'mrt_asean',
      name: 'Stasiun MRT ASEAN',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2388, longitude: 106.7987),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'mrt_senayan',
      name: 'Stasiun MRT Senayan Mastercard',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2259, longitude: 106.8021),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'mrt_istora',
      name: 'Stasiun MRT Istora Mandiri',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2209, longitude: 106.8073),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'mrt_benhil',
      name: 'Stasiun MRT Bendungan Hilir',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2155, longitude: 106.8177),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'mrt_setiabudi',
      name: 'Stasiun MRT Setiabudi Astra',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2088, longitude: 106.8206),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'mrt_dukuh_atas',
      name: 'Stasiun MRT Dukuh Atas BNI (Interchange)',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2008, longitude: 106.8228),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'mrt_bundaran_hi',
      name: 'Stasiun MRT Bundaran HI Bank DKI',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.1931, longitude: 106.8230),
      sequenceIndex: 12,
    ),

    // =========================================================================
    // 4. LRT JABODEBEK (Light Rail Transit Corridor)
    // =========================================================================
    TransitStation(
      id: 'lrt_dukuh_atas',
      name: 'Stasiun LRT Dukuh Atas',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2025, longitude: 106.8210),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'lrt_rasuna_said',
      name: 'Stasiun LRT Rasuna Said (Kuningan)',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2185, longitude: 106.8320),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'lrt_pancoran',
      name: 'Stasiun LRT Pancoran',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2435, longitude: 106.8435),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'lrt_halim',
      name: 'Stasiun LRT Halim (Whoosh KCIC)',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2440, longitude: 106.8830),
      sequenceIndex: 3,
    ),
  ];

  /// Finds the closest station to a given coordinate, optionally filtered by system.
  static TransitStation findNearestStation(
    LatLng location, {
    TransitSystem? preferredSystem,
  }) {
    TransitStation? best;
    double minDistance = double.infinity;

    for (final s in stations) {
      if (preferredSystem != null && s.system != preferredSystem) continue;
      final dist = location.distanceTo(s.point);
      if (dist < minDistance) {
        minDistance = dist;
        best = s;
      }
    }
    return best ?? stations.first;
  }

  /// Calculates a realistic public transit route connecting origin to destination.
  /// Prioritizes Transjakarta BRT and KRL Commuter Line for Jakarta and Greater Jakarta commuters.
  static TransitRouteResult buildTransitRoute({
    required LatLng origin,
    required LatLng destination,
    String? originName,
    String? destinationName,
    TransitSystem? preferredSystem,
  }) {
    // Systems to evaluate in priority order: Transjakarta, KRL, MRT, LRT
    final candidateSystems = preferredSystem != null
        ? [preferredSystem]
        : [
            TransitSystem.transjakarta,
            TransitSystem.krl,
            TransitSystem.mrt,
            TransitSystem.lrt,
          ];

    TransitRouteResult? bestResult;
    double bestScore = double.infinity;

    for (final sys in candidateSystems) {
      final res = _buildRouteForSystem(
        system: sys,
        origin: origin,
        destination: destination,
        originName: originName,
        destinationName: destinationName,
      );

      // Score = (walkOrigin + walkDest) * 2.2 + travelDistance * 0.5
      // Prioritize direct same-line options with lower total walking
      final walkPenalty = (res.walkToStationKm + res.walkFromStationKm) * 2.2;
      final score = walkPenalty + res.railDistanceKm * 0.5;

      if (score < bestScore) {
        bestScore = score;
        bestResult = res;
      }
    }

    return bestResult ??
        _buildRouteForSystem(
          system: TransitSystem.transjakarta,
          origin: origin,
          destination: destination,
          originName: originName,
          destinationName: destinationName,
        );
  }

  static TransitRouteResult _buildRouteForSystem({
    required TransitSystem system,
    required LatLng origin,
    required LatLng destination,
    String? originName,
    String? destinationName,
  }) {
    final sysStations = stations.where((s) => s.system == system).toList();
    if (sysStations.isEmpty) {
      // Fallback
      return _buildRouteForSystem(
        system: TransitSystem.krl,
        origin: origin,
        destination: destination,
        originName: originName,
        destinationName: destinationName,
      );
    }

    // Find nearest departure station and arrival station for this system
    TransitStation depStation = sysStations.first;
    double minDepDist = double.infinity;
    for (final s in sysStations) {
      final d = origin.distanceTo(s.point);
      if (d < minDepDist) {
        minDepDist = d;
        depStation = s;
      }
    }

    TransitStation arrStation = sysStations.first;
    double minArrDist = double.infinity;
    for (final s in sysStations) {
      final d = destination.distanceTo(s.point);
      if (d < minArrDist) {
        minArrDist = d;
        arrStation = s;
      }
    }

    // If both resolve to the exact same station, pick the next closest
    if (depStation.id == arrStation.id) {
      final sorted = List<TransitStation>.of(sysStations)
        ..sort(
          (a, b) => destination
              .distanceTo(a.point)
              .compareTo(destination.distanceTo(b.point)),
        );
      arrStation = sorted.firstWhere(
        (s) => s.id != depStation.id,
        orElse: () => sysStations.last,
      );
    }

    final walkToStationKm = origin.distanceTo(depStation.point);
    final walkFromStationKm = arrStation.point.distanceTo(destination);

    final intermediate = <TransitStation>[];
    final waypoints = <LatLng>[];

    // Leg 1: Walk from Origin to Departure Station / Halte
    waypoints.addAll(_interpolateCorridor(origin, depStation.point, 5));

    // Leg 2: Transit Corridor Path through all physical stations/haltes
    if (depStation.line == arrStation.line) {
      // Same line: collect all stations along the corridor in correct directional sequence
      final sameLine =
          sysStations.where((s) => s.line == depStation.line).toList();
      final depIdx = sameLine.indexWhere((s) => s.id == depStation.id);
      final arrIdx = sameLine.indexWhere((s) => s.id == arrStation.id);

      final step = depIdx < arrIdx ? 1 : -1;
      for (int i = depIdx; i != arrIdx + step; i += step) {
        if (i >= 0 && i < sameLine.length) {
          final s = sameLine[i];
          waypoints.add(s.point);
          if (s.id != depStation.id && s.id != arrStation.id) {
            intermediate.add(s);
          }
        }
      }
    } else {
      // Different lines of the same system: route through known interchange
      TransitStation? hub;
      if (system == TransitSystem.transjakarta) {
        hub = sysStations.firstWhere(
          (s) => s.id == 'tj_csw_asean' || s.id == 'tj_dukuh_atas_1',
          orElse: () => sysStations.first,
        );
      } else if (system == TransitSystem.krl) {
        hub = sysStations.firstWhere(
          (s) => s.id == 'krl_manggarai',
          orElse: () => sysStations.first,
        );
      }

      // Add dep leg to hub
      final depLine =
          sysStations.where((s) => s.line == depStation.line).toList();
      final depIdx = depLine.indexWhere((s) => s.id == depStation.id);
      final hubIdx1 = depLine.indexWhere((s) => s.id == hub?.id);

      if (hubIdx1 != -1 && depIdx != -1) {
        final step = depIdx < hubIdx1 ? 1 : -1;
        for (int i = depIdx; i != hubIdx1 + step; i += step) {
          final s = depLine[i];
          waypoints.add(s.point);
          if (s.id != depStation.id && s.id != arrStation.id) {
            intermediate.add(s);
          }
        }
      } else {
        waypoints.add(depStation.point);
        if (hub != null && hub.id != depStation.id) {
          intermediate.add(hub);
          waypoints.add(hub.point);
        }
      }

      // Add hub leg to arr
      final arrLine =
          sysStations.where((s) => s.line == arrStation.line).toList();
      final hubIdx2 = arrLine.indexWhere((s) => s.id == hub?.id);
      final arrIdx = arrLine.indexWhere((s) => s.id == arrStation.id);

      if (hubIdx2 != -1 && arrIdx != -1) {
        final step = hubIdx2 < arrIdx ? 1 : -1;
        for (int i = hubIdx2; i != arrIdx + step; i += step) {
          final s = arrLine[i];
          if (!waypoints.contains(s.point)) {
            waypoints.add(s.point);
          }
          if (s.id != depStation.id && s.id != arrStation.id) {
            if (!intermediate.contains(s)) intermediate.add(s);
          }
        }
      } else {
        if (!waypoints.contains(arrStation.point)) {
          waypoints.add(arrStation.point);
        }
      }
    }

    // Leg 3: Walk from Arrival Station / Halte to Destination
    waypoints.addAll(_interpolateCorridor(arrStation.point, destination, 5));

    // Calculate transit ride distance
    double transitKm = 0.0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      transitKm += waypoints[i].distanceTo(waypoints[i + 1]);
    }
    transitKm = max(1.0, transitKm - walkToStationKm - walkFromStationKm);

    // Speed estimates:
    // Walking: 4.5 km/h
    // Transjakarta: 24 km/h + 1 min dwell per halte
    // KRL: 40 km/h + 1.5 min dwell per station
    // MRT: 42 km/h + 1 min dwell per station
    final walkMins = ((walkToStationKm + walkFromStationKm) / 4.5 * 60).round();
    final double transitSpeed = system == TransitSystem.krl
        ? 40.0
        : (system == TransitSystem.transjakarta ? 24.0 : 42.0);
    final int dwellMinutes = intermediate.length + 2;
    final transitMins =
        max(6, (transitKm / transitSpeed * 60).round() + dwellMinutes);
    final totalDuration = Duration(minutes: walkMins + transitMins);

    // Generate authentic, turn-by-turn navigation instructions
    final cleanDepName = depStation.name.split(' (').first;
    final cleanArrName = arrStation.name.split(' (').first;

    final steps = <String>[
      'Walk ${walkToStationKm < 1.0 ? "${(walkToStationKm * 1000).round()} m" : "${walkToStationKm.toStringAsFixed(1)} km"} to $cleanDepName',
    ];

    if (system == TransitSystem.transjakarta) {
      steps.add('Tap electronic money card at $cleanDepName entrance turnstile');
      steps.add(
        'Board ${depStation.line} (Dedicated Busway Corridor) heading towards $cleanArrName',
      );
    } else if (system == TransitSystem.krl) {
      steps.add('Tap KRL Commuter Multi-Trip card at $cleanDepName fare gates');
      steps.add('Board ${depStation.line} train at Platform');
    } else {
      steps.add('Tap card and board ${depStation.system.displayName} at $cleanDepName');
    }

    if (intermediate.isNotEmpty) {
      final names = intermediate
          .map(
            (s) => s.name
                .replaceAll('Halte Transjakarta ', '')
                .replaceAll('Stasiun KRL ', '')
                .replaceAll('Stasiun MRT ', '')
                .split(' (')
                .first,
          )
          .toList();
      steps.add('Pass ${intermediate.length} transit stops: ${names.take(5).join(", ")}${names.length > 5 ? " and ${names.length - 5} more" : ""}');
    } else {
      steps.add('Direct express ride along transit corridor');
    }

    steps.add('Alight at $cleanArrName');
    steps.add(
      'Walk ${walkFromStationKm < 1.0 ? "${(walkFromStationKm * 1000).round()} m" : "${walkFromStationKm.toStringAsFixed(1)} km"} to ${destinationName ?? "Final Destination"}',
    );

    return TransitRouteResult(
      departureStation: depStation,
      arrivalStation: arrStation,
      intermediateStations: intermediate,
      transitWaypoints: waypoints,
      turnSteps: steps,
      walkToStationKm: walkToStationKm,
      railDistanceKm: transitKm,
      walkFromStationKm: walkFromStationKm,
      estimatedDuration: totalDuration,
    );
  }

  /// Interpolates coordinates between two points with slight urban grid bends
  static List<LatLng> _interpolateCorridor(
    LatLng start,
    LatLng end,
    int steps,
  ) {
    final pts = <LatLng>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final wobbleLat = sin(t * pi) * 0.0006;
      final wobbleLon = cos(t * pi) * 0.0005;
      pts.add(
        LatLng(
          latitude: double.parse(
            (start.latitude + (end.latitude - start.latitude) * t + wobbleLat)
                .toStringAsFixed(5),
          ),
          longitude: double.parse(
            (start.longitude +
                    (end.longitude - start.longitude) * t +
                    wobbleLon)
                .toStringAsFixed(5),
          ),
        ),
      );
    }
    return pts;
  }
}
