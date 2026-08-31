// Om Sai Ram
// Live Darshan screen — embeds the Shirdi live stream from sai.org.in

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_shell.dart';

// Conditional import for web platform iframe support
import 'live_darshan_web_stub.dart'
    if (dart.library.html) 'live_darshan_web.dart' as web_impl;

class LiveDarshanScreen extends StatefulWidget {
  const LiveDarshanScreen({super.key});

  @override
  State<LiveDarshanScreen> createState() => _LiveDarshanScreenState();
}

class _LiveDarshanScreenState extends State<LiveDarshanScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _hasError = false;
  /// True when the platform doesn't support WebView (e.g. Linux desktop).
  bool _unsupported = false;

  static const String _liveUrl =
      'https://sai.org.in/node/504?width=960&height=540&iframe=true';
  // On web, use the local HLS player page that fetches the stream URL via the API
  static final String _webPlayerUrl =
      'live_player.html?api=${Uri.encodeComponent(AppConstants.apiBaseUrl)}';

  @override
  void initState() {
    super.initState();
    // On web, we use a local HLS player in an iframe (sai.org.in blocks direct embedding).
    if (kIsWeb) {
      _loading = false;
      return;
    }
    _initWebView();
  }

  void _initWebView() {
    // WebViewPlatform.instance is null on platforms without a WebView
    // implementation (e.g. Linux). Guard against the assertion crash.
    if (WebViewPlatform.instance == null) {
      setState(() {
        _unsupported = true;
        _loading = false;
      });
      return;
    }
    try {
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
          onWebResourceError: (error) {
            // Ignore sub-resource errors from cross-origin iframes (common on
            // web platform); only treat main-frame failures as actual errors.
            if (error.isForMainFrame != false) {
              setState(() {
                _loading = false;
                _hasError = true;
              });
            }
          },
        ))
        ..loadRequest(Uri.parse(_liveUrl));
    } catch (_) {
      setState(() {
        _unsupported = true;
        _loading = false;
      });
    }
  }

  void _reload() {
    if (_controller == null) return;
    setState(() {
      _loading = true;
      _hasError = false;
    });
    _controller!.loadRequest(Uri.parse(_liveUrl));
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse('https://sai.org.in/live-darshan');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          if (!_unsupported)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _reload,
              tooltip: 'Refresh',
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded, color: Colors.white),
            onPressed: _openInBrowser,
            tooltip: 'Open in browser',
          ),
        ],
      ),
      body: Stack(
        children: [
          // On web platform, use the local HLS player page
          if (kIsWeb)
            web_impl.buildIframe(_webPlayerUrl),

          // Live stream webview (only when platform supports it)
          if (!kIsWeb && _controller != null)
            WebViewWidget(controller: _controller!),

          // Loading indicator
          if (_loading && !_unsupported)
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

          // Stream load error — live may be inactive
          if (_hasError && !_loading && !_unsupported)
            _FallbackView(
              icon: Icons.live_tv_rounded,
              title: 'Live Darshan Inactive',
              message: 'The live stream is currently unavailable.\n'
                  'It may be outside broadcast hours or\n'
                  'your connection may be slow.',
              onRetry: _reload,
              onBrowser: _openInBrowser,
            ),

          // Platform doesn't support WebView
          if (_unsupported)
            _FallbackView(
              icon: Icons.cast_rounded,
              title: 'Live Darshan',
              message: 'In-app live stream is not supported on this device.\n'
                  'Tap below to watch in your browser.',
              onBrowser: _openInBrowser,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared fallback / inactive-state widget
// ---------------------------------------------------------------------------

class _FallbackView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBrowser;

  const _FallbackView({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    required this.onBrowser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.saffron.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.saffron, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              if (onRetry != null) ...[
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.saffron,
                    minimumSize: const Size(200, 46),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: onBrowser,
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Watch in Browser'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  minimumSize: const Size(200, 46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
