/// Pure-Dart client for the Netease Cloud Music private API.
///
/// Entry point is [NcmClient]. Session state lives in a [CookieJar]; persist
/// `client.cookieJar.toMap()` and restore with `CookieJar.fromMap(...)`.
///
/// Low-level pieces ([NcmCrypto], [NcmRequest], [CryptoMode]) are exported for
/// advanced use — implementing endpoints not yet wrapped by [NcmClient].
library;

export 'src/ncm_client.dart' show NcmClient, SongLevel, SearchType;
export 'src/cookie_jar.dart' show CookieJar;
export 'src/request.dart'
    show NcmRequest, CryptoMode, ApiResponse, ApiException, kAnonymousToken;
export 'src/crypto.dart' show NcmCrypto;
export 'src/device.dart' show Device, OsProfile;
