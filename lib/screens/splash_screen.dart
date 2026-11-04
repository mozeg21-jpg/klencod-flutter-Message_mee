import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';
import 'chat_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _fade;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    // Staggered start: logo bounces in, then text fades up.
    _scale.forward();
    Future.delayed(const Duration(milliseconds: 500), () => _fade.forward());
    Future.delayed(const Duration(milliseconds: 1900), _next);
  }

  Future<void> _next() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final registered = (prefs.getString('uid') ?? '').isNotEmpty && (prefs.getString('name') ?? '').isNotEmpty;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, a, __) => FadeTransition(
          opacity: a,
          child: registered ? const ChatScreen() : const RegisterScreen(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    _fade.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF27878), Color(0xFFE85C5C), Color(0xFFC94444)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing rings behind the logo
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 150 + (_pulse.value * 60),
                        height: 150 + (_pulse.value * 60),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity((1 - _pulse.value) * 0.18),
                        ),
                      ),
                      Container(
                        width: 130 + (_pulse.value * 30),
                        height: 130 + (_pulse.value * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity((1 - _pulse.value) * 0.22),
                        ),
                      ),
                      child!,
                    ],
                  ),
                  child: ScaleTransition(
                    scale: CurvedAnimation(parent: _scale, curve: Curves.elasticOut),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text('A',
                                style: TextStyle(color: Color(0xFFE85C5C), fontSize: 60, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
                        .animate(CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic)),
                    child: const Text(
                      'Ahmed Saad Community',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _fade,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white, valueColor: null),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
