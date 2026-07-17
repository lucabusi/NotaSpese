/// Supported currencies (ISO 4217). Static list, no external API.
/// No HRK: Croatian kuna replaced by EUR in 2023.
enum Currency {
  // Frequent (shown on top of the picker, spec §8) — EUR first.
  eur('EUR', 'Euro', '€', 2, frequente: true),
  usd('USD', 'Dollaro USA', r'$', 2, frequente: true),
  jpy('JPY', 'Yen giapponese', '¥', 0, frequente: true),
  gbp('GBP', 'Sterlina britannica', '£', 2, frequente: true),
  chf('CHF', 'Franco svizzero', 'CHF', 2, frequente: true),
  rsd('RSD', 'Dinaro serbo', 'дин.', 2, frequente: true),
  aed('AED', 'Dirham EAU', 'د.إ', 2, frequente: true),
  sgd('SGD', 'Dollaro di Singapore', r'S$', 2, frequente: true),
  // Others (alphabetical by code).
  all('ALL', 'Lek albanese', 'L', 2),
  aud('AUD', 'Dollaro australiano', r'A$', 2),
  bam('BAM', 'Marco bosniaco', 'KM', 2),
  bgn('BGN', 'Lev bulgaro', 'лв', 2),
  brl('BRL', 'Real brasiliano', r'R$', 2),
  cad('CAD', 'Dollaro canadese', r'C$', 2),
  cny('CNY', 'Yuan cinese', '¥', 2),
  czk('CZK', 'Corona ceca', 'Kč', 2),
  dkk('DKK', 'Corona danese', 'kr', 2),
  hkd('HKD', 'Dollaro di Hong Kong', r'HK$', 2),
  huf('HUF', 'Fiorino ungherese', 'Ft', 2),
  idr('IDR', 'Rupia indonesiana', 'Rp', 2),
  ils('ILS', 'Nuovo shekel israeliano', '₪', 2),
  inr('INR', 'Rupia indiana', '₹', 2),
  krw('KRW', 'Won sudcoreano', '₩', 0),
  kwd('KWD', 'Dinaro kuwaitiano', 'د.ك', 3),
  mkd('MKD', 'Denar macedone', 'ден', 2),
  mxn('MXN', 'Peso messicano', r'MX$', 2),
  myr('MYR', 'Ringgit malese', 'RM', 2),
  nok('NOK', 'Corona norvegese', 'kr', 2),
  nzd('NZD', 'Dollaro neozelandese', r'NZ$', 2),
  php('PHP', 'Peso filippino', '₱', 2),
  pln('PLN', 'Złoty polacco', 'zł', 2),
  qar('QAR', 'Riyal del Qatar', 'ر.ق', 2),
  ron('RON', 'Leu romeno', 'lei', 2),
  sar('SAR', 'Riyal saudita', 'ر.س', 2),
  sek('SEK', 'Corona svedese', 'kr', 2),
  thb('THB', 'Baht thailandese', '฿', 2),
  try_('TRY', 'Lira turca', '₺', 2),
  twd('TWD', 'Nuovo dollaro taiwanese', r'NT$', 2),
  vnd('VND', 'Dong vietnamita', '₫', 0),
  zar('ZAR', 'Rand sudafricano', 'R', 2);

  const Currency(this.code, this.nome, this.symbol, this.decimalDigits,
      {this.frequente = false});

  /// ISO 4217 code, stored as-is in DB column `spese.valuta`.
  /// Never store [name]: `try_` exists only because `try` is a Dart keyword.
  final String code;
  final String nome;
  final String symbol;
  final int decimalDigits;
  final bool frequente;

  /// Frequent currencies for the top of the picker, spec order.
  static List<Currency> get frequenti =>
      values.where((c) => c.frequente).toList();

  static Currency? fromCode(String code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
