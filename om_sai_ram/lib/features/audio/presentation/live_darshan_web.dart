// Web-specific implementation for Live Darshan iframe embedding.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

bool _registered = false;

Widget buildIframe(String url) {
  const viewType = 'live-darshan-iframe';

  if (!_registered) {
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..setAttribute('allow',
            'autoplay; encrypted-media; fullscreen; picture-in-picture');
      return iframe;
    });
  }

  return const HtmlElementView(viewType: viewType);
}
