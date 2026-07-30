# Finance Suit color-system integration

Finance Suit consumes a vendored Flutter snapshot of the canonical Building
Suit color system. Product widgets use Material semantic roles or
`FinanceSuitSemanticColors`; they must not import raw palette constants.

## Canonical source

- Repository: `https://github.com/tareq-abdelwhap/building-suit`
- Source commit: `51f6513e366b284af2770d25e090ea2928412edb`
- Required token ancestor: `8de7ff8c556c90042e13d7782f48f27ffeaa560f`
- Upstream artifact:
  `.docs/building-suit-brand-guidelines/07-design-tokens/flutter_colors.dart`
- Vendored artifact: `lib/app/theme/building_suit_colors.dart`

`building_suit_colors.dart` is generated upstream. Do not edit it locally.
To synchronize it, verify that the intended Building Suit commit contains the
required ancestor, replace the vendored file byte-for-byte with the upstream
generated artifact, then run the theme tests and the raw-color audit.

## Semantic adapter

`AppTheme` maps canonical roles into Material 3 `ColorScheme` and component
themes. `FinanceSuitSemanticColors` exposes roles Material does not name:
interaction overlays, mode-specific focus, status families, charts, skeletons,
strong control borders, and intentional brand surfaces.

The static Play/legal pages use the same canonical light/dark role values in
`legal/styles.css`, including mode-specific `:focus-visible` rings. Their
`theme-color` metadata follows the canonical app-background role in each mode.

| Previous use | Previous value | Canonical semantic role |
| --- | --- | --- |
| Dark app background | `#0A111A` | `roleDarkBackground` (`#0E1114`) |
| Dark cards/app bar | `#14233A` | `roleDarkSurface` (`#151A1F`) |
| Dark raised/modal layers | `#1B2E47` | `roleDarkSurfaceRaised` / `roleDarkSurfaceOverlay` |
| Dark borders | `#2E3F52` | `roleDarkBorder` or `roleDarkBorderStrong` by function |
| Broad dark muted text | `#7E97B3` | `roleDarkTextMuted` (`#B1B8C0`) |
| Dark disabled text | `#4A5A6E` | `roleDarkTextDisabled` (`#66717D`) |
| Light focus | Gold 700 | `roleLightFocusRing` |
| Dark focus | Highlight Gold | `roleDarkFocusRing` |
| Selection tint | Local alpha | Mode-specific `selectedOverlay` |
| Chart defaults | Library defaults/local status colors | Canonical chart and categorical roles |
| Loading tracks | Generic muted surface | Canonical skeleton base/highlight |

Building Navy remains limited to official artwork, splash/app-icon brand
surfaces, and the semantic `brandSurface` role. Gold is an action/focus/accent,
never a positive-income or debt status.

## Raw-color allowlist

Product-owned Dart source may contain color literals only in the generated
`building_suit_colors.dart` snapshot. `Colors.transparent` is allowed where
Flutter requires suppressing Material surface tint or a resting focus border.
This document retains retired literals only in the explicit migration table
above so future audits can identify and reject them.

`legal/styles.css` is the small semantic adapter for the standalone legal
pages and records its upstream SHA beside its canonical role literals. The four
legal HTML files repeat only the light/dark app-background values because HTML
`theme-color` metadata cannot reference CSS custom properties.

The following native/vector resources are official Finance Suit artwork and
remain unchanged:

- `assets/branding/finance_suit_app_icon.svg`
- `assets/branding/finance_suit_mark.svg`
- `android/app/src/main/res/drawable/finance_suit_splash_mark.xml`
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- `android/app/src/main/res/drawable/ic_launcher_monochrome.xml`
- `android/app/src/main/res/values/colors.xml`

These files intentionally retain the approved Building Navy, Pearl White,
Premium Gold, or Android monochrome artwork colors.
