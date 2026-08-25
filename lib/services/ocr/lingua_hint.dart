/// Currencies whose country maps to exactly one receipt language, used to
/// infer the hint when the trip has none. `JPY` also switches ML Kit to the
/// japanese recognizer; `PLN` does not (polish is latin-script) but still
/// puts the polish profile first in the parser's language vote, which is
/// what decides the total on a degraded `paragon fiskalny`.
/// Other currencies stay on auto (null): `EUR`/`USD` span several
/// languages, and serbian Cyrillic is deliberately routed to Claude.
const Map<String, String> _linguaPerValuta = {'JPY': 'ja', 'PLN': 'pl'};

/// Effective OCR language hint for a trip: an explicit `linguaDefault`
/// always wins. When absent (older trips predate the field, or the user
/// left it on auto) infer from the trip's currency (see [_linguaPerValuta]).
String? effectiveLinguaHint(String? linguaDefault, String? valutaDefault) =>
    linguaDefault ?? _linguaPerValuta[valutaDefault];
