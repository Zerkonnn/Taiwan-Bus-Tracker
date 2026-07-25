// PTX API data models — mirrors src/types/index.ts from the React Native version

import '../utils/app_strings.dart';

const String defaultCity = 'Taichung';

const Map<String, String> cityLabels = {
  'Taipei': '臺北市',
  'NewTaipei': '新北市',
  'Taichung': '臺中市',
  'Tainan': '臺南市',
  'Kaohsiung': '高雄市',
  'Taoyuan': '桃園市',
  'Hsinchu': '新竹市',
  'Keelung': '基隆市',
  'HsinchuCounty': '新竹縣',
  'MiaoliCounty': '苗栗縣',
  'ChanghuaCounty': '彰化縣',
  'NantouCounty': '南投縣',
  'YunlinCounty': '雲林縣',
  'ChiayiCounty': '嘉義縣',
  'PingtungCounty': '屏東縣',
  'YilanCounty': '宜蘭縣',
  'HualienCounty': '花蓮縣',
  'TaitungCounty': '臺東縣',
};

class BusPosition {
  final double lat;
  final double lon;

  const BusPosition({required this.lat, required this.lon});

  factory BusPosition.fromJson(Map<String, dynamic> json) => BusPosition(
        lat: (json['PositionLat'] as num).toDouble(),
        lon: (json['PositionLon'] as num).toDouble(),
      );
}

class LocalizedName {
  final String zhTw;
  final String en;

  const LocalizedName({required this.zhTw, required this.en});

  factory LocalizedName.fromJson(Map<String, dynamic> json) => LocalizedName(
        zhTw: json['Zh_tw'] as String? ?? '',
        en: json['En'] as String? ?? '',
      );

  /// Picks the name for the given language, falling back to whichever is non-empty.
  String forLang(AppLanguage lang) {
    if (lang == AppLanguage.en) return en.isNotEmpty ? en : zhTw;
    return zhTw.isNotEmpty ? zhTw : en;
  }
}

String cityLabel(AppLanguage lang, String city) {
  return lang == AppLanguage.zh ? (cityLabels[city] ?? city) : city;
}

class BusRealTime {
  final String plateNumb;
  final String routeUID;
  final LocalizedName routeName;
  final int direction; // 0 = outbound 去程, 1 = inbound 回程
  final int busStatus; // 0=normal, 1=starting, 2=not operating
  final BusPosition busPosition;
  final double speed;
  final String updateTime;

  const BusRealTime({
    required this.plateNumb,
    required this.routeUID,
    required this.routeName,
    required this.direction,
    required this.busStatus,
    required this.busPosition,
    required this.speed,
    required this.updateTime,
  });

  factory BusRealTime.fromJson(Map<String, dynamic> json) => BusRealTime(
        plateNumb: json['PlateNumb'] as String? ?? '',
        routeUID: json['RouteUID'] as String? ?? '',
        routeName: json['RouteName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['RouteName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        direction: json['Direction'] as int? ?? 0,
        busStatus: json['BusStatus'] as int? ?? 0,
        busPosition: json['BusPosition'] is Map<String, dynamic>
            ? BusPosition.fromJson(json['BusPosition'] as Map<String, dynamic>)
            : const BusPosition(lat: 0, lon: 0),
        speed: (json['Speed'] as num?)?.toDouble() ?? 0,
        updateTime: json['UpdateTime'] as String? ?? '',
      );
}

class BusStop {
  final String stopUID;
  final String stopID;
  final LocalizedName stopName;
  final BusPosition stopPosition;
  final String stopAddress;
  final String bearing;

  const BusStop({
    required this.stopUID,
    required this.stopID,
    required this.stopName,
    required this.stopPosition,
    required this.stopAddress,
    required this.bearing,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) => BusStop(
        stopUID: json['StopUID'] as String? ?? '',
        stopID: json['StopID'] as String? ?? '',
        stopName: json['StopName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['StopName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        stopPosition: json['StopPosition'] is Map<String, dynamic>
            ? BusPosition.fromJson(json['StopPosition'] as Map<String, dynamic>)
            : const BusPosition(lat: 0, lon: 0),
        stopAddress: json['StopAddress'] as String? ?? '',
        bearing: json['Bearing'] as String? ?? '',
      );
}

class EstimatedArrival {
  final String plateNumb;
  final String routeUID;
  final LocalizedName routeName;
  final int direction;
  final String stopUID;
  final String stopID;
  final LocalizedName stopName;
  final int estimateTime; // seconds; -1 = no data/not departed, 0 = at stop
  final int stopCountDown;
  final String updateTime;
  // PTX StopStatus: 0=normal, 1=not yet departed, 2=no service, 3=ended, 4=no passing
  final int stopStatus;

  const EstimatedArrival({
    required this.plateNumb,
    required this.routeUID,
    required this.routeName,
    required this.direction,
    required this.stopUID,
    required this.stopID,
    required this.stopName,
    required this.estimateTime,
    required this.stopCountDown,
    required this.updateTime,
    this.stopStatus = 0,
  });

  factory EstimatedArrival.fromJson(Map<String, dynamic> json) =>
      EstimatedArrival(
        plateNumb: json['PlateNumb'] as String? ?? '',
        routeUID: json['RouteUID'] as String? ?? '',
        routeName: json['RouteName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['RouteName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        direction: json['Direction'] as int? ?? 0,
        stopUID: json['StopUID'] as String? ?? '',
        stopID: json['StopID'] as String? ?? '',
        stopName: json['StopName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['StopName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        // Null EstimateTime means no tracking data — use -1 (not 0=arriving)
        estimateTime: json['EstimateTime'] as int? ?? -1,
        stopCountDown: json['StopCountDown'] as int? ?? 0,
        updateTime: json['UpdateTime'] as String? ?? '',
        stopStatus: json['StopStatus'] as int? ?? 0,
      );
}

class BusRoute {
  final String routeUID;
  final String routeID;
  final LocalizedName routeName;
  final String departureStopNameZh;
  final String destinationStopNameZh;
  final String city;
  final String cityCode;

  const BusRoute({
    required this.routeUID,
    required this.routeID,
    required this.routeName,
    required this.departureStopNameZh,
    required this.destinationStopNameZh,
    required this.city,
    required this.cityCode,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) => BusRoute(
        routeUID: json['RouteUID'] as String? ?? '',
        routeID: json['RouteID'] as String? ?? '',
        routeName: json['RouteName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['RouteName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        departureStopNameZh: json['DepartureStopNameZh'] as String? ?? '',
        destinationStopNameZh: json['DestinationStopNameZh'] as String? ?? '',
        city: json['City'] as String? ?? '',
        cityCode: json['CityCode'] as String? ?? '',
      );
}

class RouteStop {
  final String routeUID;
  final int direction;
  final String stopUID;
  final LocalizedName stopName;
  final BusPosition stopPosition;
  final int stopSequence;

  const RouteStop({
    required this.routeUID,
    required this.direction,
    required this.stopUID,
    required this.stopName,
    required this.stopPosition,
    required this.stopSequence,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        routeUID: json['RouteUID'] as String? ?? '',
        direction: json['Direction'] as int? ?? 0,
        stopUID: json['StopUID'] as String? ?? '',
        stopName: json['StopName'] is Map<String, dynamic>
            ? LocalizedName.fromJson(json['StopName'] as Map<String, dynamic>)
            : const LocalizedName(zhTw: '', en: ''),
        stopPosition: json['StopPosition'] is Map<String, dynamic>
            ? BusPosition.fromJson(json['StopPosition'] as Map<String, dynamic>)
            : const BusPosition(lat: 0, lon: 0),
        stopSequence: json['StopSequence'] as int? ?? 0,
      );
}

// App-internal: stop with distance from user
class NearbyStop {
  final BusStop stop;
  final double distance; // meters

  const NearbyStop({required this.stop, required this.distance});
}