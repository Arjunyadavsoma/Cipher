import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  static final title = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  static final body = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Colors.black,
    height: 1.45,
  );

  static final caption = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: const Color(0xff6E6E73),
  );

  static final input = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );
}