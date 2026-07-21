/// Effective OCR language hint for a trip: an explicit `linguaDefault`
/// always wins. When absent (older trips predate the field, or the user
/// left it on auto) infer from the trip's currency — `JPY` is the only
/// mapping worth having, since it is the one currency-tied script ML Kit
/// has a dedicated recognizer for. Other currencies (including the
/// Serbian/Cyrillic case, which ML Kit cannot render at all and is
/// deliberately routed to Claude instead) stay on auto (null).
String? effectiveLinguaHint(String? linguaDefault, String? valutaDefault) =>
    linguaDefault ?? (valutaDefault == 'JPY' ? 'ja' : null);
