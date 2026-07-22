// Om Sai Ram
// Live Darshan screen — embeds the Shirdi live stream from sai.org.in

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_shell.dart';

class LiveDarshanScreen extends StatefulWidget {
  const LiveDarshanScreen({super.key});

  @override
  State<LiveDarshanScreen> createState() => _LiveDarshanScreenState();
}

class _LiveDarshanScreenState extends State<LiveDarshanScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;

  static const String _liveUrl =
      'https://sai.org.in/node/504?width=960&height=540&iframe=true';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 11; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() {
          _loading = true;
          _hasError = false;
        }),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (_) => setState(() {
          _loading = false;
          _hasError = true;
        }),
      ))
      ..loadRequest(Uri.parse(_liveUrl));
  }

  void _reload() {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    _controller.loadRequest(Uri.parse(_liveUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Live Darshan',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Live stream webview
          WebViewWidget(controller: _controller),

          // Loading indicator
          if (_loading)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.saffron),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Live Darshan...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Error state
          if (_hasError && !_loading)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.signal_wifi_off_rounded,
                        color: Colors.white.withOpacity(0.5), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load live stream.\nPlease check your internet connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.saffron,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
