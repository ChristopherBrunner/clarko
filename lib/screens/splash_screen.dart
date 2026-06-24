import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import 'home_screen.dart';

/// Branded animated splash: the white Pacifico "C" springs in (matching the
/// launcher icon / native splash, pinned to screen centre), then the "Clarko"
/// wordmark + tagline rise up below it, before fading through to the home
/// screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markFade;
  late final Animation<double> _markScale;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    );
    _markFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 0.55, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    ));
    _wordFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.8, curve: Curves.easeOut),
    );
    _wordSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
    ));

    _controller.forward().whenComplete(_goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => HomeScreen(state: widget.state),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF00796B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.2,
              colors: [Color(0xFF009688), Color(0xFF00796B)],
            ),
          ),
          child: Stack(
            children: [
              // C pinned to the screen centre, ink-centred via the image so it
              // sits squarely over the wordmark (Text would offset it by the
              // glyph's side-bearing/tail).
              Center(
                child: FadeTransition(
                  opacity: _markFade,
                  child: ScaleTransition(
                    scale: _markScale,
                    child: Image.asset(
                      'assets/clarko_c.png',
                      height: 130,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              // Wordmark + tagline float below centre without shifting the C.
              Align(
                alignment: const Alignment(0, 0.34),
                child: SlideTransition(
                  position: _wordSlide,
                  child: FadeTransition(
                    opacity: _wordFade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Clarko',
                          style: TextStyle(
                            fontFamily: 'Clarko',
                            fontSize: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'stay on track',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
