import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData buildDsmTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = Color(dark ? 0xffedf2fa : 0xff17243a);
  final muted = Color(dark ? 0xffb7c4d8 : 0xff536178);
  final canvas = Color(dark ? 0xff101722 : 0xfff4f6fa);
  final surface = Color(dark ? 0xff1a2433 : 0xffffffff);
  final border = Color(dark ? 0xff354257 : 0xffdce3ee);
  final scheme =
      ColorScheme.fromSeed(seedColor: Color(0xff245ac8), brightness: brightness)
          .copyWith(
    primary: Color(dark ? 0xffa8c5ff : 0xff245ac8),
    onPrimary: Color(dark ? 0xff102d61 : 0xffffffff),
    secondary: Color(dark ? 0xffa8c5ff : 0xff245ac8),
    onSecondary: Color(dark ? 0xff102d61 : 0xffffffff),
    background: canvas,
    onBackground: ink,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: border,
  );
  final base = ThemeData(brightness: brightness, colorScheme: scheme);
  final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: border));
  return base.copyWith(
    primaryColor: scheme.primary,
    scaffoldBackgroundColor: canvas,
    backgroundColor: canvas,
    cardColor: surface,
    dividerColor: border,
    disabledColor: muted.withOpacity(.65),
    extensions: <ThemeExtension>[
      AppTheme(
          titleColor: ink,
          placeholderColor: muted,
          primaryColor: dark ? surface : ink,
          progressColor: border)
    ],
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
          headline5: TextStyle(
              fontSize: 26,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: ink),
          headline6:
              TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink),
          subtitle1: TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: ink),
          subtitle2: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: ink),
          bodyText1: TextStyle(fontSize: 15, height: 1.5, color: ink),
          bodyText2: TextStyle(fontSize: 15, height: 1.45, color: ink),
          caption: TextStyle(fontSize: 13, height: 1.4, color: muted),
        ),
    iconTheme: IconThemeData(color: muted, size: 22),
    appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        iconTheme: IconThemeData(color: ink),
        actionsIconTheme: IconThemeData(color: ink),
        titleTextStyle:
            TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w600),
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
    tabBarTheme: TabBarTheme(
        labelColor: scheme.primary,
        unselectedLabelColor: muted,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: scheme.primary, width: 3))),
    cardTheme: CardTheme(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: border))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        hintStyle: TextStyle(fontSize: 14, color: muted),
        labelStyle: TextStyle(color: muted, fontSize: 14)),
    listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
            minimumSize: Size(48, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)))),
    dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
  );
}

class AppTheme extends ThemeExtension<AppTheme> {
  static AppTheme of(BuildContext context) {
    return Theme.of(context).extension<AppTheme>();
  }

  final Color primaryColor;
  final Color placeholderColor;
  final Color titleColor;
  final Color progressColor;
  AppTheme({
    this.primaryColor,
    this.placeholderColor,
    this.titleColor,
    this.progressColor,
  });

  @override
  AppTheme copyWith({
    Color primaryColor,
    Color placeholderColor,
    Color titleColor,
    Color progressColor,
  }) {
    return AppTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      placeholderColor: placeholderColor ?? this.placeholderColor,
      titleColor: titleColor ?? this.titleColor,
      progressColor: progressColor ?? this.progressColor,
    );
  }

  @override
  AppTheme lerp(ThemeExtension<AppTheme> other, double t) {
    if (other is! AppTheme) return this;
    final theme = other as AppTheme;
    return AppTheme(
        primaryColor: Color.lerp(primaryColor, theme.primaryColor, t),
        placeholderColor:
            Color.lerp(placeholderColor, theme.placeholderColor, t),
        titleColor: Color.lerp(titleColor, theme.titleColor, t),
        progressColor: Color.lerp(progressColor, theme.progressColor, t));
  }
}
