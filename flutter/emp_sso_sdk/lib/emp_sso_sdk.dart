/// EMP Shared SSO SDK for Flutter.
///
/// Public entry point — re-exports tất cả API mà app con cần để tích hợp
/// SSO Handoff với EMP Mobile.
library emp_sso_sdk;

export 'src/emp_sso.dart';
export 'src/config/sso_config.dart';
export 'src/models/sso_user.dart';
export 'src/models/token_response.dart';
export 'src/models/deep_link_params.dart';
export 'src/models/sso_auth_event.dart';
export 'src/exceptions/sso_exceptions.dart';
