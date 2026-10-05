import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ───────────────────────── CONFIG ─────────────────────────
const String kAppName = 'VIP PhotoShoot Library';
const String kSiteUrl = 'https://vip-photoshoot-library.netlify.app';
const Color kBg = Color(0xFF0D0610);
const Color kAccent = Color(0xFFFF8FC7);

// Set to false when you switch to your real AdMob IDs.
const bool kUseTestAds = true; // REPLACE WITH YOUR REAL ADMOB ID (then set this to false)

const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
const String _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
const String _realBanner = 'ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY'; // REPLACE WITH YOUR REAL ADMOB ID (Banner unit)
const String _realInterstitial = 'ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ'; // REPLACE WITH YOUR REAL ADMOB ID (Interstitial unit)

const String kBannerUnitId = kUseTestAds ? _testBanner : _realBanner;
const String kInterstitialUnitId = kUseTestAds ? _testInterstitial : _realInterstitial;

/// Max 1 interstitial every 2 minutes.
const Duration kInterstitialGap = Duration(minutes: 2);

const String kContactEmail = 'your-email@example.com'; // REPLACE WITH YOUR REAL CONTACT EMAIL

// ───────────────────────── APP ─────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const VipApp());
}

class VipApp extends StatelessWidget {
  const VipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAccent, surface: kBg),
        appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
      ),
      home: const SplashScreen(),
    );
  }
}

// ───────────────────────── SPLASH ─────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WebHome()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/logo.png', width: 140, height: 140),
            ),
            const SizedBox(height: 24),
            const Text(kAppName,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: .3)),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: kAccent),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── BANNER (reused on every screen) ─────────────────────────
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: kBannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner failed: $error');
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}

// ───────────────────────── MAIN WEBVIEW SCREEN ─────────────────────────
class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  late final WebViewController _c;
  InterstitialAd? _interstitial;
  DateTime? _lastInterstitial;
  Completer<void>? _refreshDone;
  int _progress = 0;
  bool _atTop = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..setOnScrollPositionChange((change) => _atTop = change.y <= 0)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _error = false),
        onPageFinished: (_) => _finishRefresh(),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) setState(() => _error = true);
          _finishRefresh();
        },
        // Fires for normal loads AND the site's in-page (Next.js) navigation.
        onUrlChange: (change) => _maybeShowInterstitial(change.url),
        onNavigationRequest: _handleNavigation,
      ));
    _setup();
    _loadInterstitial();
  }

  Future<void> _setup() async {
    // Tag the user agent so the website can hide things that don't work in an
    // app (Google popup sign-in is blocked by Google inside WebViews).
    final ua = await _c.getUserAgent();
    await _c.setUserAgent('${ua ?? ''} VIPPhotoShootApp');
    await _c.loadRequest(Uri.parse(kSiteUrl));
  }

  // Keep the site inside the app; send everything else (WhatsApp, social, mail) outside.
  FutureOr<NavigationDecision> _handleNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    final siteHost = Uri.parse(kSiteUrl).host;
    if (uri.host == siteHost || uri.scheme == 'about' || uri.scheme == 'blob' || uri.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  // ── Interstitial ──
  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: kInterstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) {
          _interstitial = null;
          debugPrint('Interstitial failed: $e');
        },
      ),
    );
  }

  /// Shows an interstitial when a photo CATEGORY page (/library/<category>)
  /// opens, at most once every [kInterstitialGap].
  void _maybeShowInterstitial(String? url) {
    if (url == null) return;
    final path = Uri.tryParse(url)?.path ?? '';
    if (!RegExp(r'^/library/[^/]+/?$').hasMatch(path)) return;

    final now = DateTime.now();
    if (_lastInterstitial != null && now.difference(_lastInterstitial!) < kInterstitialGap) return;

    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    _interstitial = null;
    _lastInterstitial = now;
    ad.show();
  }

  // ── Pull to refresh ──
  Future<void> _refresh() {
    _refreshDone = Completer<void>();
    _c.reload();
    // Never leave the spinner hanging on a bad connection.
    return _refreshDone!.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  }

  void _finishRefresh() {
    final done = _refreshDone;
    if (done != null && !done.isCompleted) done.complete();
    _refreshDone = null;
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Back button: go back in the site's history, exit the app when there is none.
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_progress > 0 && _progress < 100)
                LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: kAccent, backgroundColor: kBg),
              Expanded(
                child: Stack(
                  children: [
                    _error ? _offline() : _webView(),
                    Positioned(left: 6, bottom: 6, child: _infoMenu()),
                  ],
                ),
              ),
              const BannerSlot(), // bottom banner
            ],
          ),
        ),
      ),
    );
  }

  Widget _webView() {
    return LayoutBuilder(
      builder: (context, box) => RefreshIndicator(
        color: kAccent,
        backgroundColor: kBg,
        // Only allow pull-to-refresh when the web page is scrolled to the very top.
        notificationPredicate: (n) => _atTop && n.depth == 0,
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: box.maxHeight,
            child: WebViewWidget(
              controller: _c,
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _offline() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: kAccent),
            const SizedBox(height: 16),
            const Text("Can't reach the library",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Check your internet connection and try again.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                setState(() => _error = false);
                _c.loadRequest(Uri.parse(kSiteUrl));
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // Small floating menu → About / Privacy Policy (required for AdMob approval).
  Widget _infoMenu() {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.info_outline_rounded, size: 20),
        tooltip: 'About',
        onSelected: (v) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => v == 'about' ? const AboutPage() : const PrivacyPage(),
        )),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'about', child: Text('About')),
          PopupMenuItem(value: 'privacy', child: Text('Privacy Policy')),
        ],
      ),
    );
  }
}

// ───────────────────────── ABOUT & PRIVACY PAGES ─────────────────────────
class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: children),
          ),
          const BannerSlot(), // banner on every screen
        ],
      ),
    );
  }
}

Widget _h(String t) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kAccent)),
    );
Widget _p(String t) => Text(t, style: const TextStyle(height: 1.5, color: Colors.white70));

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _InfoPage(title: 'About', children: [
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset('assets/logo.png', width: 96, height: 96),
        ),
      ),
      const SizedBox(height: 14),
      const Center(child: Text(kAppName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      const Center(child: Text('Version 1.0.0', style: TextStyle(color: Colors.white54))),
      _h('What is this app?'),
      _p('VIP PhotoShoot Library is a library of 50,000+ ready-to-use AI photography prompts. '
          'Upload your photo to an AI tool such as ChatGPT or Google Gemini, paste a prompt, and get '
          'studio-quality portraits in new outfits, poses and scenes while keeping your own face and hairstyle.'),
      _h('Free trial & plans'),
      _p('New members get a free trial. After that you can continue with a 7-day, 1-month, 1-year or lifetime plan.'),
      _h('Made by'),
      _p('Coach VIP Tech Academy.'),
      _h('Contact'),
      _p(kContactEmail),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => launchUrl(Uri.parse('$kSiteUrl/terms'), mode: LaunchMode.externalApplication),
        child: const Text('Terms of Use'),
      ),
    ]);
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _InfoPage(title: 'Privacy Policy', children: [
      _p('Last updated: 2026. This policy explains how $kAppName ("the app") handles information.'),
      _h('Information we collect'),
      _p('To create an account we collect your name, email address, phone number and password. '
          'Passwords are handled by Google Firebase Authentication and are never visible to us. '
          'Account data is stored securely with Google Firebase.'),
      _h('Your photos'),
      _p('Photos you pick in the app are only previewed on your device. We do not upload them to our servers.'),
      _h('Advertising (Google AdMob)'),
      _p('The app shows ads provided by Google AdMob. AdMob may collect and use the Android Advertising ID, '
          'IP address and device and usage information to serve and measure ads, which may be personalised. '
          'You can reset your advertising ID or opt out of personalised ads in your Android settings '
          '(Settings → Google → Ads). Learn more at policies.google.com/technologies/ads.'),
      _h('Payments'),
      _p('Subscriptions are paid by bank transfer outside the app. We do not collect card details.'),
      _h('Children'),
      _p('The app is not directed at children under 13.'),
      _h('Deleting your data'),
      _p('To correct or delete your account information, contact us at $kContactEmail.'),
      _h('Full policy'),
      const SizedBox(height: 4),
      OutlinedButton(
        onPressed: () => launchUrl(Uri.parse('$kSiteUrl/privacy'), mode: LaunchMode.externalApplication),
        child: const Text('Open full Privacy Policy online'),
      ),
    ]);
  }
}
