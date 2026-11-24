// Web-specific implementation for Live Darshan iframe embedding.
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool _registered = false;

Widget buildIframe(String url, {Key? key}) {
  const viewType = 'live-darshan-iframe';

  if (!_registered) {
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId, {Object? params}) {
      final iframe = web.HTMLIFrameElement()
        ..src = params as String
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..setAttribute('allow',
            'autoplay; encrypted-media; fullscreen; picture-in-picture');
      return iframe;
    });
  }

  return HtmlElementView(key: key, viewType: viewType, creationParams: url);
}
