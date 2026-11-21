import 'package:flutter/material.dart';

/// mybillwill brand colours, taken from the logo.
class Brand {
  static const name = 'mybillwill';
  static const tagline = 'Organize. Track. Pay.';

  static const teal = Color(0xFF0E6E70); // "my" and the arrows
  static const tealDark = Color(0xFF07524F);
  static const tealLight = Color(0xFFE3F1F0);
  static const gold = Color(0xFFE3AE34); // gold arrow
  static const goldLight = Color(0xFFFBF1D8);
  static const navy = Color(0xFF283F4C); // "billwill"
  static const slate = Color(0xFF5A6A74); // tagline
  static const background = Color(0xFFF5F7F7);
  static const border = Color(0xFFDCE4E4);

  static const logoFull = 'assets/images/logo_full.png';
  static const logoMark = 'assets/images/logo_mark.png';
}

/// Logo image: full (with mybillwill text) or just the arrows mark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 40, this.full = false});
  final double height;
  final bool full;
  @override
  Widget build(BuildContext context) =>
      Image.asset(full ? Brand.logoFull : Brand.logoMark, height: height, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
}

/// Mark + "mybillwill" wordmark in brand colours, for headers.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 22});
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        BrandLogo(height: size * 1.15),
        SizedBox(width: size * 0.4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'my', style: TextStyle(color: Brand.teal, fontSize: size, fontWeight: FontWeight.w800)),
            TextSpan(text: 'billwill', style: TextStyle(color: Brand.navy, fontSize: size, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]);
}
