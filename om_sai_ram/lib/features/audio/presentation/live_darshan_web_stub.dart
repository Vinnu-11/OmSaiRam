// Stub for non-web platforms — never actually called.
import 'package:flutter/widgets.dart';

Widget buildIframe(String url) {
  throw UnsupportedError('Iframe is only supported on web platform');
}
