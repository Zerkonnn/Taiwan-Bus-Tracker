// App-wide translation strings — Traditional Chinese / English toggle.
// Flat key → {zh, en} lookup, plus small template helpers for compound
// strings (mins remaining, walk hints, etc.) that can't be a static map entry.

enum AppLanguage { zh, en }

class AppStrings {
  AppStrings._();

  static const Map<String, Map<AppLanguage, String>> _strings = {
    // ── Shared ──────────────────────────────────────────────────────────
    'outbound': {AppLanguage.en: 'Outbound', AppLanguage.zh: '去程'},
    'inbound': {AppLanguage.en: 'Inbound', AppLanguage.zh: '回程'},
    'route': {AppLanguage.en: 'Route', AppLanguage.zh: '路線'},
    'searching': {AppLanguage.en: 'Searching…', AppLanguage.zh: '搜尋中…'},
    'retry': {AppLanguage.en: 'Retry', AppLanguage.zh: '重試'},
    'drive': {AppLanguage.en: 'Drive', AppLanguage.zh: '開車'},
    'walk': {AppLanguage.en: 'Walk', AppLanguage.zh: '步行'},
    'updatesEvery30s': {
      AppLanguage.en: 'Updates every 30s',
      AppLanguage.zh: '每 30 秒更新'
    },
    'arrivingSoonHeader': {
      AppLanguage.en: 'ARRIVING SOON',
      AppLanguage.zh: '即將抵達'
    },
    'noBusesArrivingSoon': {
      AppLanguage.en: 'No buses arriving soon',
      AppLanguage.zh: '近期無公車抵達'
    },
    'resultsHeader': {AppLanguage.en: 'RESULTS', AppLanguage.zh: '搜尋結果'},
    'searchRoutesTitle': {
      AppLanguage.en: 'Search Routes',
      AppLanguage.zh: '搜尋路線'
    },
    'tooManyRequestsRetry': {
      AppLanguage.en: 'Too many requests\nWait a moment and retry',
      AppLanguage.zh: '請求過多\n請稍後再試'
    },

    // ── Map screen ──────────────────────────────────────────────────────
    'searchLocationHint': {
      AppLanguage.en: 'Search location…',
      AppLanguage.zh: '搜尋地點…'
    },
    'findingRoutes': {
      AppLanguage.en: 'Finding routes…',
      AppLanguage.zh: '正在尋找路線…'
    },
    'noRoutesFound': {
      AppLanguage.en: 'No routes found',
      AppLanguage.zh: '找不到路線'
    },
    'getDirectionsToStop': {
      AppLanguage.en: 'Get directions to this stop',
      AppLanguage.zh: '前往此站的路線指引'
    },
    'stopLocationUnavailable': {
      AppLanguage.en: 'Stop location data unavailable',
      AppLanguage.zh: '站牌位置資料無法取得'
    },
    'nearbyTab': {AppLanguage.en: 'Nearby', AppLanguage.zh: '附近'},
    'routesTab': {AppLanguage.en: 'Routes', AppLanguage.zh: '路線'},
    'gettingLocation': {
      AppLanguage.en: 'Getting location…',
      AppLanguage.zh: '正在取得位置…'
    },
    'noNearbyStops': {
      AppLanguage.en: 'No nearby bus stops',
      AppLanguage.zh: '附近沒有公車站'
    },
    'busServiceInactiveShort': {
      AppLanguage.en: 'Bus service inactive (06:00–23:00)',
      AppLanguage.zh: '公車服務未營運（06:00–23:00）'
    },
    'approach': {AppLanguage.en: 'Approach', AppLanguage.zh: '即將進站'},
    'servOver': {AppLanguage.en: 'Serv Over', AppLanguage.zh: '今日停駛'},
    'arriving': {AppLanguage.en: 'Arriving', AppLanguage.zh: '即將抵達'},
    'enterRouteNumberHint': {
      AppLanguage.en: 'Enter route number (e.g. 52)',
      AppLanguage.zh: '輸入路線號碼（例如 52）'
    },
    'searchFailedTryAgain': {
      AppLanguage.en: 'Search failed, try again',
      AppLanguage.zh: '搜尋失敗，請再試一次'
    },
    'routeNotFound': {
      AppLanguage.en: 'Route not found',
      AppLanguage.zh: '找不到路線'
    },
    'searchTaichungRoutes': {
      AppLanguage.en: 'Search Taichung bus routes',
      AppLanguage.zh: '搜尋台中公車路線'
    },
    'noLocationsFound': {
      AppLanguage.en: 'No locations found',
      AppLanguage.zh: '找不到地點'
    },

    // ── Search screen ───────────────────────────────────────────────────
    'enterRouteNumberEllipsis': {
      AppLanguage.en: 'Enter route number, e.g. 52…',
      AppLanguage.zh: '輸入路線號碼，例如 52…'
    },
    'tooManyRequestsWait': {
      AppLanguage.en: 'Too many requests — wait a moment and try again',
      AppLanguage.zh: '請求過多，請稍後再試'
    },
    'searchUnavailable': {
      AppLanguage.en: 'Search unavailable',
      AppLanguage.zh: '搜尋服務無法使用'
    },
    'popularRoutesHeader': {
      AppLanguage.en: 'POPULAR ROUTES',
      AppLanguage.zh: '熱門路線'
    },
    'enterBusRouteNumberHint': {
      AppLanguage.en: 'Enter a bus route number, e.g. "52" or "301"',
      AppLanguage.zh: '輸入公車路線號碼，例如「52」或「301」'
    },
    'tryRouteNumberLike': {
      AppLanguage.en: 'Try a route number like "52" or "301"',
      AppLanguage.zh: '請嘗試輸入路線號碼，例如「52」或「301」'
    },

    // ── Route detail screen ─────────────────────────────────────────────
    'serviceInactiveLong': {
      AppLanguage.en:
          'Bus service is inactive right now (operating hours: 06:00–23:00). Stop list is still available.',
      AppLanguage.zh: '公車服務目前未營運（營運時間 06:00–23:00）。站牌列表仍可查看。'
    },
    'couldNotLoadStops': {
      AppLanguage.en: 'Could not load stops',
      AppLanguage.zh: '無法載入站牌資料'
    },
    'noStopData': {AppLanguage.en: 'No stop data', AppLanguage.zh: '無站牌資料'},

    // ── Stop detail screen ──────────────────────────────────────────────
    'loadingEllipsis': {AppLanguage.en: 'Loading…', AppLanguage.zh: '載入中…'},
    'couldNotLoadArrivals': {
      AppLanguage.en: 'Could not load arrivals',
      AppLanguage.zh: '無法載入到站資料'
    },

    // ── Favourites screen ───────────────────────────────────────────────
    'savedRoutesTitle': {
      AppLanguage.en: 'Saved Routes',
      AppLanguage.zh: '收藏路線'
    },
    'noSavedRoutesYet': {
      AppLanguage.en: 'No saved routes yet',
      AppLanguage.zh: '尚無收藏路線'
    },
    'starRouteHint': {
      AppLanguage.en: 'Star a route on its detail page to save it here',
      AppLanguage.zh: '在路線詳情頁點擊星號即可收藏至此'
    },

    // ── Scan screen ─────────────────────────────────────────────────────
    'scanBusStopTitle': {
      AppLanguage.en: 'Scan Bus Stop',
      AppLanguage.zh: '掃描公車站牌'
    },
    'camera': {AppLanguage.en: 'Camera', AppLanguage.zh: '相機'},
    'gallery': {AppLanguage.en: 'Gallery', AppLanguage.zh: '相簿'},
    'readingSign': {
      AppLanguage.en: 'Reading sign…',
      AppLanguage.zh: '正在辨識站牌…'
    },
    'noRouteNumbersFound': {
      AppLanguage.en:
          'No bus route numbers found in this image.\nMake sure the sign is clear and well-lit.',
      AppLanguage.zh: '在這張圖片中找不到公車路線號碼。\n請確認站牌清晰且光線充足。'
    },
    'couldNotProcessImage': {
      AppLanguage.en: 'Could not process image. Please try again.',
      AppLanguage.zh: '無法處理圖片，請再試一次。'
    },
    'notFoundInTaichung': {
      AppLanguage.en: 'NOT FOUND IN TAICHUNG',
      AppLanguage.zh: '台中未找到符合路線'
    },
    'pointCameraAtSign': {
      AppLanguage.en: 'Point your camera at a bus stop sign',
      AppLanguage.zh: '將相機對準公車站牌'
    },
    'appWillReadRouteNumbers': {
      AppLanguage.en:
          "The app will read the route numbers and show each bus's schedule",
      AppLanguage.zh: '應用程式會辨識路線號碼並顯示各班公車的時刻資訊'
    },
    'tapForStopsEtas': {
      AppLanguage.en: 'Tap for stops & ETAs ›',
      AppLanguage.zh: '點擊查看站牌與到站時間 ›'
    },

    // ── Bottom nav ──────────────────────────────────────────────────────
    'mapTab': {AppLanguage.en: 'Map', AppLanguage.zh: '地圖'},
    'savedTab': {AppLanguage.en: 'Saved', AppLanguage.zh: '收藏'},

    // ── formatEta ───────────────────────────────────────────────────────
    'notDeparted': {AppLanguage.en: 'Not departed', AppLanguage.zh: '尚未發車'},
  };

  static String t(AppLanguage lang, String key) {
    return _strings[key]?[lang] ?? key;
  }

  // ── Template helpers (can't be a flat map entry) ──────────────────────

  static String route(AppLanguage lang, String routeName) {
    return lang == AppLanguage.zh ? '$routeName 路線' : 'Route $routeName';
  }

  static String stopFallbackLabel(AppLanguage lang, int sequence) {
    return lang == AppLanguage.zh ? '站牌 $sequence' : 'Stop $sequence';
  }

  static String toDestination(AppLanguage lang, String destination) {
    return lang == AppLanguage.zh ? '往 $destination' : 'To $destination';
  }

  static String minsLabel(AppLanguage lang, int mins) {
    if (lang == AppLanguage.zh) return '$mins 分';
    return mins == 1 ? '1 min' : '$mins min';
  }

  static String approxMinsLabel(AppLanguage lang, int mins) {
    return lang == AppLanguage.zh ? '約 $mins 分鐘' : '~$mins min';
  }

  static String walkHintLabel(
      AppLanguage lang, int mins, String distLabel, String destination) {
    return lang == AppLanguage.zh
        ? '步行 $mins 分鐘（$distLabel）至 $destination'
        : 'Walk ${mins}min ($distLabel) to $destination';
  }

  static String busesInService(AppLanguage lang, int count) {
    return lang == AppLanguage.zh ? '$count 輛公車行駛中' : '$count buses in service';
  }

  static String noRoutesFoundForQuery(AppLanguage lang, String query) {
    return lang == AppLanguage.zh
        ? '找不到符合「$query」的路線'
        : 'No routes found for "$query"';
  }

  static String detectedBusRoutes(AppLanguage lang, int count) {
    if (lang == AppLanguage.zh) return '偵測到 $count 條公車路線';
    return 'DETECTED $count BUS ROUTE${count == 1 ? '' : 'S'}';
  }

  static String numbersDetectedNoneMatched(AppLanguage lang, String numbers) {
    return lang == AppLanguage.zh
        ? '偵測到號碼（$numbers），但皆未符合台中公車路線。'
        : 'Numbers detected ($numbers) but none matched Taichung bus routes.';
  }
}
