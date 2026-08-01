import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

/// The SVG data and direction behavior for one approved Finance Suit glyph.
class FinanceSuitGlyph {
  const FinanceSuitGlyph(this.data, {this.mirrorInRtl = false});

  final List<List<dynamic>> data;
  final bool mirrorInRtl;
}

/// The only renderer for app-owned interface icons.
///
/// It keeps the free Hugeicons Stroke Rounded treatment consistent and applies
/// the Suit icon rules for optical stroke, inherited color, accessibility, and
/// RTL direction. A null [semanticLabel] marks decorative artwork; enclosing
/// buttons and labeled rows provide their own semantics.
class FinanceSuitIcon extends StatelessWidget {
  const FinanceSuitIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final FinanceSuitGlyph glyph;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? IconTheme.of(context).size ?? 24;
    Widget artwork = Center(
      widthFactor: 1,
      heightFactor: 1,
      child: HugeIcon(
        icon: glyph.data,
        size: effectiveSize,
        color: color,
        strokeWidth: _strokeWidth(effectiveSize),
      ),
    );

    if (glyph.mirrorInRtl && Directionality.of(context) == TextDirection.rtl) {
      artwork = Transform.flip(flipX: true, child: artwork);
    }

    artwork = ExcludeSemantics(child: artwork);
    final label = semanticLabel;
    if (label == null) return artwork;
    return Semantics(image: true, label: label, child: artwork);
  }

  static double _strokeWidth(double size) {
    if (size <= 16) return 1.5;
    if (size <= 24) return 2;
    return 2.5;
  }
}

/// Central semantic catalog for every app-owned interface glyph.
///
/// Feature code depends on these roles, never on the third-party icon API, so
/// the free Stroke Rounded family cannot be mixed with another visual style.
abstract final class FinanceSuitIcons {
  static const accountBalance = FinanceSuitGlyph(HugeIconsStrokeRounded.bank);
  static const accountBalanceWallet = FinanceSuitGlyph(
    HugeIconsStrokeRounded.wallet02,
  );
  static const add = FinanceSuitGlyph(HugeIconsStrokeRounded.add01);
  static const addCircle = FinanceSuitGlyph(HugeIconsStrokeRounded.addCircle);
  static const attachMoney = FinanceSuitGlyph(
    HugeIconsStrokeRounded.dollarReceive01,
  );
  static const barChart = FinanceSuitGlyph(HugeIconsStrokeRounded.chartColumn);
  static const beachAccess = FinanceSuitGlyph(HugeIconsStrokeRounded.beach);
  static const bolt = FinanceSuitGlyph(HugeIconsStrokeRounded.flash);
  static const brightness = FinanceSuitGlyph(HugeIconsStrokeRounded.sun01);
  static const calculate = FinanceSuitGlyph(HugeIconsStrokeRounded.calculator);
  static const calendarToday = FinanceSuitGlyph(
    HugeIconsStrokeRounded.calendar03,
  );
  static const category = FinanceSuitGlyph(HugeIconsStrokeRounded.gridView);
  static const celebration = FinanceSuitGlyph(HugeIconsStrokeRounded.party);
  static const check = FinanceSuitGlyph(HugeIconsStrokeRounded.tick02);
  static const checkCircle = FinanceSuitGlyph(
    HugeIconsStrokeRounded.checkmarkCircle02,
  );
  static const chevronLeft = FinanceSuitGlyph(
    HugeIconsStrokeRounded.arrowLeft01,
    mirrorInRtl: true,
  );
  static const chevronRight = FinanceSuitGlyph(
    HugeIconsStrokeRounded.arrowRight01,
    mirrorInRtl: true,
  );
  static const close = FinanceSuitGlyph(HugeIconsStrokeRounded.cancel01);
  static const delete = FinanceSuitGlyph(HugeIconsStrokeRounded.delete02);
  static const edit = FinanceSuitGlyph(HugeIconsStrokeRounded.edit02);
  static const email = FinanceSuitGlyph(HugeIconsStrokeRounded.mail01);
  static const error = FinanceSuitGlyph(HugeIconsStrokeRounded.alertCircle);
  static const eventAvailable = FinanceSuitGlyph(
    HugeIconsStrokeRounded.calendarCheckIn02,
  );
  static const eventBusy = FinanceSuitGlyph(HugeIconsStrokeRounded.calendarOff);
  static const event = calendarToday;
  static const expandMore = FinanceSuitGlyph(
    HugeIconsStrokeRounded.arrowDown01,
  );
  static const history = FinanceSuitGlyph(
    HugeIconsStrokeRounded.transactionHistory,
  );
  static const home = FinanceSuitGlyph(HugeIconsStrokeRounded.home03);
  static const info = FinanceSuitGlyph(
    HugeIconsStrokeRounded.informationCircle,
  );
  static const label = FinanceSuitGlyph(HugeIconsStrokeRounded.tag01);
  static const language = FinanceSuitGlyph(
    HugeIconsStrokeRounded.languageCircle,
  );
  static const link = FinanceSuitGlyph(HugeIconsStrokeRounded.link01);
  static const lockOpen = FinanceSuitGlyph(
    HugeIconsStrokeRounded.squareUnlock02,
  );
  static const lock = FinanceSuitGlyph(HugeIconsStrokeRounded.squareLock02);
  static const logout = FinanceSuitGlyph(
    HugeIconsStrokeRounded.logout03,
    mirrorInRtl: true,
  );
  static const manageSearch = FinanceSuitGlyph(
    HugeIconsStrokeRounded.searchList01,
  );
  static const medicalServices = FinanceSuitGlyph(
    HugeIconsStrokeRounded.medicalFile,
  );
  static const menu = FinanceSuitGlyph(HugeIconsStrokeRounded.menu01);
  static const money = FinanceSuitGlyph(HugeIconsStrokeRounded.cash01);
  static const moreTime = FinanceSuitGlyph(HugeIconsStrokeRounded.clockPlus);
  static const password = FinanceSuitGlyph(
    HugeIconsStrokeRounded.squareLockPassword,
  );
  static const pauseCircle = FinanceSuitGlyph(
    HugeIconsStrokeRounded.pauseCircle,
  );
  static const payments = FinanceSuitGlyph(HugeIconsStrokeRounded.payment01);
  static const pending = FinanceSuitGlyph(HugeIconsStrokeRounded.hourglass);
  static const person = FinanceSuitGlyph(HugeIconsStrokeRounded.user);
  static const play = FinanceSuitGlyph(HugeIconsStrokeRounded.play);
  static const priceChange = FinanceSuitGlyph(
    HugeIconsStrokeRounded.moneyExchange03,
  );
  static const receiptLong = FinanceSuitGlyph(
    HugeIconsStrokeRounded.receiptText,
  );
  static const refresh = FinanceSuitGlyph(HugeIconsStrokeRounded.refresh);
  static const removeCircle = FinanceSuitGlyph(
    HugeIconsStrokeRounded.minusSignCircle,
  );
  static const requestQuote = FinanceSuitGlyph(
    HugeIconsStrokeRounded.invoice03,
  );
  static const savings = FinanceSuitGlyph(HugeIconsStrokeRounded.piggyBank);
  static const search = FinanceSuitGlyph(HugeIconsStrokeRounded.search01);
  static const settings = FinanceSuitGlyph(HugeIconsStrokeRounded.settings02);
  static const shoppingCart = FinanceSuitGlyph(
    HugeIconsStrokeRounded.shoppingCart01,
  );
  static const sort = FinanceSuitGlyph(HugeIconsStrokeRounded.sorting05);
  static const star = FinanceSuitGlyph(HugeIconsStrokeRounded.star);
  static const swapHoriz = FinanceSuitGlyph(
    HugeIconsStrokeRounded.arrowLeftRight,
  );
  static const trendingUp = FinanceSuitGlyph(
    HugeIconsStrokeRounded.chartIncrease,
  );
  static const tune = FinanceSuitGlyph(
    HugeIconsStrokeRounded.slidersHorizontal,
  );
  static const undo = FinanceSuitGlyph(
    HugeIconsStrokeRounded.undo,
    mirrorInRtl: true,
  );
  static const visibility = FinanceSuitGlyph(HugeIconsStrokeRounded.view);
  static const visibilityOff = FinanceSuitGlyph(HugeIconsStrokeRounded.viewOff);
  static const volunteerActivism = FinanceSuitGlyph(
    HugeIconsStrokeRounded.handHelping,
  );
  static const wallet = FinanceSuitGlyph(HugeIconsStrokeRounded.wallet01);
  static const warning = FinanceSuitGlyph(HugeIconsStrokeRounded.alert02);
  static const work = FinanceSuitGlyph(HugeIconsStrokeRounded.work);
}
