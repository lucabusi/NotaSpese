import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/language_profiles.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';

void main() {
  // Real JP receipts (see test/real_receipts_accuracy_test.dart) print
  // full-width digits, letter-spaced keywords and percentages next to the
  // total; these are the unit-level guards for that handling.
  group('normalizeOcrText', () {
    test('full-width digits and latin become half-width', () {
      expect(normalizeOcrText('計 ５５２０円 Ｎｏ００２'), '計 5520円 No002');
    });

    test('ideographic space and full-width yen normalized', () {
      expect(normalizeOcrText('合　計 ￥1,489'), '合 計 ¥1,489');
    });

    test('kana and kanji left untouched', () {
      expect(normalizeOcrText('ヨークベニマル 領収証'), 'ヨークベニマル 領収証');
    });

    test('space after thousands comma rejoined (ML Kit splits ¥1, 489)', () {
      expect(normalizeOcrText('合計 1, 508'), '合計 1,508');
      expect(normalizeOcrText('買上金額 ¥1, 489'), '買上金額 ¥1,489');
    });

    test('decimal comma with fewer than 3 digits untouched', () {
      expect(normalizeOcrText('totale 1, 50'), 'totale 1, 50');
    });
  });

  // ML Kit's japanese model reads the ¥ glyph as a leading `4` attached to
  // the amount (`¥6,775` → `46,775`, misura su foto reali 2026-07-22).
  group('fixYenGlyphs', () {
    test('leading 4 on a comma-grouped number becomes ¥', () {
      expect(fixYenGlyphs('小計 46,775'), '小計 ¥6,775');
      expect(fixYenGlyphs('クレジット- (417,780)'), 'クレジット- (¥17,780)');
      expect(fixYenGlyphs('合計金額: 48,480'), '合計金額: ¥8,480');
    });

    test('numbers not starting with 4 or without comma grouping untouched', () {
      expect(fixYenGlyphs('合計 17,780'), '合計 17,780');
      expect(fixYenGlyphs('アボカドコロッケ 4680'), 'アボカドコロッケ 4680');
      expect(fixYenGlyphs('金額 4,500'), '金額 4,500');
    });

    test('4 inside a longer number untouched', () {
      expect(fixYenGlyphs('会員番号 946,000'), '会員番号 946,000');
      expect(fixYenGlyphs('¥46,680'), '¥46,680');
    });
  });

  group('ja receipts - spacing, full-width and percent handling', () {
    final ja = languageProfiles['ja']!;

    test('letter-spaced total keyword still matches', () {
      const text = '小 計 額   ¥1,710\n合  計   ¥1,710';
      expect(extractAmount(text, ja), 1710);
    });

    test('bare 計 total on a full-width taxi slip', () {
      final text = normalizeOcrText('定額  ５５２０円\n計  ５５２０円');
      expect(extractAmount(text, ja), 5520);
    });

    test('percentage next to a keyword is not taken as the total', () {
      const text = '次回のお会計から「10%割引」\n合計   ¥17,780';
      expect(extractAmount(text, ja), 17780);
    });

    test('spaced kanji date parsed', () {
      expect(
        extractDate('2026年 7月 5日(日) 20:07', ja, now: DateTime(2026, 7, 20)),
        DateTime(2026, 7, 5),
      );
    });

    test('ISO dashed date parsed', () {
      expect(
        extractDate('2026-07-11 22:11:07', ja, now: DateTime(2026, 7, 20)),
        DateTime(2026, 7, 11),
      );
    });

    test('クレジット payment line wins over slip-number fallback', () {
      // JP_01 reale: la riga 合計 è uccisa dai negativi 税/対象, l'unico
      // totale pulito è la riga di pagamento carta.
      const text = '10%税率対象合計 ¥6,680\n'
          'クレジット ¥6,680\n'
          'シートNo:90246';
      expect(extractAmount(text, ja), 6680);
    });

    test('keyword line without value never steals from a negative next line',
        () {
      // Taxi JP_05 reale: `クレジットカード支払、` non ha numeri e la riga
      // dopo è la tax-rate line — il totale vero sta sul bare 計.
      const text = 'クレジットカード支払、\n'
          '消費税率 10. 09%\n'
          '計 5520円';
      expect(extractAmount(text, ja), 5520);
    });

    test('金額 label on a card slip wins over processing numbers', () {
      // JP_14 reale: nessuna keyword 合計/クレジット con valore, il totale
      // sta su una riga `金額 ¥2,640`.
      const text = '処理通番 374753\n金額 ¥2,640';
      expect(extractAmount(text, ja), 2640);
    });

    test('merchant label wins over document-type header lines', () {
      const text = '[クレジットカードご利用票]\n'
          '加盟店名:      ユニオン コマース\n'
          'ご利用日時: 2026/07/11 14:55:07';
      expect(extractVendor(text), 'ユニオン コマース');
    });
  });

  group('parseAmountToken', () {
    test('commaDecimal: 1.234,56 -> 1234.56', () {
      expect(
        parseAmountToken('1.234,56', AmountNumberFormat.commaDecimal),
        1234.56,
      );
    });

    test('commaDecimal with attached currency: €12,50 -> 12.50', () {
      expect(
        parseAmountToken('€12,50', AmountNumberFormat.commaDecimal),
        12.50,
      );
    });

    test('dotDecimal: 1,234.56 -> 1234.56', () {
      expect(
        parseAmountToken('1,234.56', AmountNumberFormat.dotDecimal),
        1234.56,
      );
    });

    test('integerOnly with attached currency: ¥1,200 -> 1200.0', () {
      expect(
        parseAmountToken('¥1,200', AmountNumberFormat.integerOnly),
        1200.0,
      );
    });

    test('integerOnly plain: 1,234 -> 1234.0', () {
      expect(
        parseAmountToken('1,234', AmountNumberFormat.integerOnly),
        1234.0,
      );
    });

    test('non-numeric token -> null', () {
      expect(parseAmountToken('abc', AmountNumberFormat.dotDecimal), null);
    });

    test('separators-only token -> null', () {
      expect(parseAmountToken('.,', AmountNumberFormat.commaDecimal), null);
    });
  });

  group('extractAmount - total keyword per language', () {
    test('IT: totale keyword on same line, rightmost number wins', () {
      final text = 'Articolo 5 - Totale dovuto € 45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });

    test('EN: total keyword picks value', () {
      final text = 'Item 1 5.00\nTotal 25.00';
      expect(extractAmount(text, languageProfiles['en']!), 25.0);
    });

    test('JA: 合計 keyword picks value', () {
      final text = '小計 900円\n合計 1,000円';
      expect(extractAmount(text, languageProfiles['ja']!), 1000.0);
    });

    test('SR: ukupno keyword picks value', () {
      final text = 'Međuzbir 500,00\nUkupno 650,00';
      expect(extractAmount(text, languageProfiles['sr']!), 650.0);
    });

    test('SR: Cyrillic Укупно keyword picks value (case-insensitive match)',
        () {
      final text = 'Међузбир 500,00\nУкупно 1.250,00';
      expect(extractAmount(text, languageProfiles['sr']!), 1250.0);
    });

    test('DE: gesamtbetrag keyword picks value', () {
      final text = 'Zwischensumme 10,00\nGesamtbetrag 55,00';
      expect(extractAmount(text, languageProfiles['de']!), 55.0);
    });

    test('DE: gesamtbetrag outranks generic gesamt', () {
      final text = 'Gesamt 10,00\nGesamtbetrag 55,00';
      expect(extractAmount(text, languageProfiles['de']!), 55.0);
    });
  });

  group('extractAmount - negative keyword lines excluded', () {
    test('IT: "Subtotale" line excluded even though it contains "totale"', () {
      final text = 'Subtotale 30,00\nTotale 45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });

    test('EN: "Subtotal" line excluded even though it contains "total"', () {
      final text = 'Subtotal 20.00\nTotal 25.00';
      expect(extractAmount(text, languageProfiles['en']!), 25.0);
    });
  });

  group('extractAmount - OCR column layout', () {
    test('IT: keyword line has no number, value on following line', () {
      final text = 'Totale\n45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });
  });

  group('extractAmount - keyword priority and repeated keyword', () {
    test('EN: earlier-priority keyword wins over later keyword with bigger value', () {
      final text = 'Total 10.00\nAmount Due 999.00';
      expect(extractAmount(text, languageProfiles['en']!), 10.0);
    });

    test('EN: same keyword repeated, max value wins', () {
      final text = 'Total 10.00\nTotal 20.00';
      expect(extractAmount(text, languageProfiles['en']!), 20.0);
    });
  });

  group('extractAmount - no keyword fallback', () {
    test('IT: no keyword, plausible maximum wins (excludes > 1,000,000)', () {
      final text = 'Articolo 12,50\nArticolo 99,90\nCodice 9999999,00';
      expect(extractAmount(text, languageProfiles['it']!), 99.90);
    });

    test('IT: fallback excludes negative-keyword lines from the max', () {
      final text = 'Riga1 12,50\nIva 999999,00\nRiga2 40,00';
      expect(extractAmount(text, languageProfiles['it']!), 40.0);
    });

    test('EN: no numbers at all -> null', () {
      const text = 'No numbers here at all';
      expect(extractAmount(text, languageProfiles['en']!), null);
    });
  });

  group('extractDate', () {
    test('IT: dd/MM/yyyy format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Scontrino\nData: 15/07/2026\nTotale 10,00';
      expect(
        extractDate(text, languageProfiles['it']!, now: now),
        DateTime(2026, 7, 15),
      );
    });

    test('EN: MM/dd/yyyy format extracted (day > 12 disambiguates)', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Receipt\n07/16/2026\nTotal 25.00';
      expect(
        extractDate(text, languageProfiles['en']!, now: now),
        DateTime(2026, 7, 16),
      );
    });

    test('JA: yyyy年M月d日 format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'レシート\n2026年7月18日\n合計 1,000円';
      expect(
        extractDate(text, languageProfiles['ja']!, now: now),
        DateTime(2026, 7, 18),
      );
    });

    test('DE: dd.MM.yyyy format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Quittung\n17.07.2026\nGesamtbetrag 55,00';
      expect(
        extractDate(text, languageProfiles['de']!, now: now),
        DateTime(2026, 7, 17),
      );
    });

    test('future date is rejected, search continues to a plausible one', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Data ordine: 01/01/2027\nData scontrino: 10/07/2026';
      expect(
        extractDate(text, languageProfiles['it']!, now: now),
        DateTime(2026, 7, 10),
      );
    });

    test('date older than 730 days is rejected', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Data: 10/07/2023';
      expect(extractDate(text, languageProfiles['it']!, now: now), null);
    });

    test('no date in text -> null', () {
      final now = DateTime(2026, 7, 18);
      const text = 'Nessuna data qui';
      expect(extractDate(text, languageProfiles['it']!, now: now), null);
    });
  });

  group('extractVendor', () {
    test('first clean line returned trimmed', () {
      const text = '  Bar Centrale  \nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'Bar Centrale');
    });

    test('P.IVA line skipped, next clean line returned', () {
      const text = 'P.IVA 12345678901\nRistorante Da Mario\nVia Roma 1';
      expect(extractVendor(text), 'Ristorante Da Mario');
    });

    test('phone line skipped', () {
      const text = 'Tel: 02-1234567\nFarmacia Centrale\nVia Milano 5';
      expect(extractVendor(text), 'Farmacia Centrale');
    });

    test('CAP (zip) line skipped', () {
      const text = '20100 Milano\nSupermercato Alfa\nVia Torino 2';
      expect(extractVendor(text), 'Supermercato Alfa');
    });

    test('URL line skipped', () {
      const text = 'www.negozio.it\nNegozio Beta\nVia Napoli 3';
      expect(extractVendor(text), 'Negozio Beta');
    });

    test('line of mostly digits/punctuation skipped', () {
      const text = '---***---\nCaffetteria Gamma\nVia Torino 9';
      expect(extractVendor(text), 'Caffetteria Gamma');
    });

    test('vendor below noisy header lines is still found (6-line window)', () {
      const text = '12345\nTel: 0212345\nwww.site.it\nVendor Name';
      expect(extractVendor(text), 'Vendor Name');
    });

    test('only first 6 non-empty lines considered, all noisy -> null', () {
      const text = '12345\nTel: 0212345\nwww.site.it\n'
          '99999\nTel: 0298765\nhttp://a.b\nVendor Name';
      expect(extractVendor(text), null);
    });

    test('hotel line not discarded by tel pattern (word boundary check)', () {
      const text = 'Hotel Bristol\nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'Hotel Bristol');
    });

    test('phone line still skipped with Tel. prefix', () {
      const text = 'Tel. 02 1234567\nTrattoria da Mario\nVia Torino 8';
      expect(extractVendor(text), 'Trattoria da Mario');
    });

    test('iPhone Store not discarded by phone pattern (word boundary check)', () {
      const text = 'iPhone Store\nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'iPhone Store');
    });

    test('empty text -> null', () {
      expect(extractVendor(''), null);
    });

    // Fix da misura ML Kit su foto reali (2026-07-22): il nome insegna è
    // spesso un logo garbled sulla prima riga, mentre la ragione sociale
    // pulita sta subito sotto.
    group('ML Kit real-photo glyph fixes', () {
      test('garbled logo line with # skipped in favor of the clean line', () {
        // JP_01 reale: logo HARD・OFF letto `HARD-oF#`.
        const text = 'HARD-oF#\nハードオフ宇都宮駅東店\nTEL: 028-664-2556';
        expect(extractVendor(text), 'ハードオフ宇都宮駅東店');
      });

      test('ASCII hyphen between katakana becomes long-vowel mark', () {
        // JP_03 reale: `ヨ-クベニマル`.
        const text = 'ヨ-クベニマル\nお取替·返品の際はレシートをお持ち';
        expect(extractVendor(text), 'ヨークベニマル');
      });

      test('single stray latin letter glued to a katakana name stripped', () {
        // JP_04 reale: logo letto come `K` attaccata all insegna.
        const text = 'Kヨークベニマル\nお取替·返品の際はレシートをお持ち';
        expect(extractVendor(text), 'ヨークベニマル');
      });

      test('merchant label value cut at 係員 even without slash', () {
        // JP_06 reale: `加盟店名宇都宮MS係員65` (JP_05 ha lo slash, JP_06 no).
        const text = 'クレジットカード売上票\n加盟店名宇都宮MS係員65';
        expect(extractVendor(text), '宇都宮MS');
      });

      test('CJK 口 between latin letters becomes O', () {
        // JP_10 reale: `LAWS口N`.
        const text = 'LAWS口N\n宇者都宮駅西口店';
        expect(extractVendor(text), 'LAWSON');
      });

      test('leading punctuation dust stripped', () {
        // JP_12 reale: `·健太鼓子`.
        const text = '·健太鼓子\n,宇部雪鉄子館';
        expect(extractVendor(text), '健太鼓子');
      });

      test('legitimate latin hyphen and interpunct names untouched', () {
        expect(extractVendor('SEVEN-ELEVEN\nVia Roma 1'), 'SEVEN-ELEVEN');
        expect(extractVendor('HARD・OFF\n宇都宮駅東店'), 'HARD・OFF');
      });

      test('merchant label 加盟店名 misread as カ盟店名 still recognized', () {
        // Taxi reale (2026-07-22): 加 (kanji) letto カ (katakana), la riga
        // label non veniva più riconosciuta e il parser cadeva sul rumore
        // in cima allo scontrino (`No0 O 1`).
        const text = 'No0 O 1\nクレジットカード売上票\nお客様控\n'
            '2026年07月22日17:43\n車番 2023\n乗務員No 266\n'
            'カ盟店名 宇都宮MS/係員266';
        expect(extractVendor(text), '宇都宮MS');
      });
    });
  });

  group('inferCurrencyFromText', () {
    test('€ -> EUR', () {
      expect(inferCurrencyFromText('Totale € 45,00'), 'EUR');
    });

    test('£ -> GBP', () {
      expect(inferCurrencyFromText('Total £45.00'), 'GBP');
    });

    test(r'$ -> USD', () {
      expect(inferCurrencyFromText(r'Total $45.00'), 'USD');
    });

    test('CHF -> CHF', () {
      expect(inferCurrencyFromText('Total CHF 45.00'), 'CHF');
    });

    test('дин. -> RSD', () {
      expect(inferCurrencyFromText('Ukupno 500 дин.'), 'RSD');
    });

    test('din -> RSD', () {
      expect(inferCurrencyFromText('Ukupno 500 din'), 'RSD');
    });

    test('RSD code -> RSD', () {
      expect(inferCurrencyFromText('Ukupno 500 RSD'), 'RSD');
    });

    test('¥ -> JPY', () {
      expect(inferCurrencyFromText('合計 ¥1000'), 'JPY');
    });

    test('円 -> JPY', () {
      expect(inferCurrencyFromText('合計 1000円'), 'JPY');
    });

    test('no known currency marker -> null', () {
      expect(inferCurrencyFromText('Total 45.00'), null);
    });
  });

  group('ReceiptParser.parse - language selection', () {
    test('hint promotes a non-default-first profile out of a genuine tie', () {
      // No keyword/date/currency signal for any profile -> every profile
      // scores identically (vendor-only, +1). Without a hint, default map
      // order ('it' first) breaks the tie; with linguaHint: 'de', 'de' is
      // tried first and wins the same tie instead. This would fail if
      // linguaHint were ignored (both calls would return 'it').
      const text = 'Negozio Alfa';

      final withoutHint = ReceiptParser().parse(text);
      expect(withoutHint.lingua, 'it');

      final withHint = ReceiptParser().parse(text, linguaHint: 'de');
      expect(withHint.lingua, 'de');
    });

    test('no hint, no script -> default profile order breaks the tie', () {
      const text = 'Bar Roma\nTotale € 12,50';
      final result = ReceiptParser().parse(text);
      expect(result.lingua, 'it');
    });

    test('JA text without hint is picked via script detection', () {
      const text = 'レシート\n合計 1,000円';
      final result = ReceiptParser().parse(text);
      expect(result.lingua, 'ja');
      expect(result.importo, 1000.0);
    });

    test('wrong hint overridden when another profile scores better', () {
      const text = 'Restaurant\nGesamtbetrag 55,00';
      final result = ReceiptParser().parse(text, linguaHint: 'it');
      expect(result.lingua, 'de');
      expect(result.importo, 55.0);
    });

    test(
      'regression: keyword line with no adjacent value scores as fallback, '
      'not keyword (importo still resolved via fallback-max)',
      () {
        // "Totale" matches the IT keyword, but neither that line nor the
        // next has a number -> extractAmount falls back to the plain
        // "12,50" found elsewhere. The scorer must award 1 point (fallback),
        // not 2 (keyword), even though a keyword line is present.
        const text = 'Totale\nGrazie\nArrivederci 12,50';
        final result = ReceiptParser().parse(text, linguaHint: 'it');
        expect(result.lingua, 'it');
        expect(result.importo, 12.5);
      },
    );

    test(
      'regression: fallback-only amount does not get the keyword bonus, '
      'so a genuine keyword-path amount elsewhere wins',
      () {
        // IT's "Totale" keyword line has no adjacent value (real amount
        // "87,50" is only found via fallback-max, scoring 1 point), while
        // DE's "Gesamtbetrag" keyword line does have an adjacent value
        // (scoring 2 points). DE must win outright (score 4 vs 3). Before
        // the fix, the scorer credited IT's fallback amount as if it came
        // from the keyword line (wrongly +2), tying DE at 4-4 and letting
        // the hinted 'it' win the tie instead of the correct 'de'.
        const text = 'Totale\nNegozio Alfa\nVia Roma 1\nGesamtbetrag 87,50';
        final result = ReceiptParser().parse(text, linguaHint: 'it');
        expect(result.lingua, 'de');
        expect(result.importo, 87.5);
      },
    );
  });

  group('ReceiptParser.parse - currency cascade', () {
    test('explicit symbol overrides the winning profile default currency', () {
      const text = 'Ristorante Roma\nTotale \$45,00';
      final result = ReceiptParser().parse(text, linguaHint: 'it');
      expect(result.valuta, 'USD');
    });

    test('EN text without a symbol -> valuta null (form uses trip default)', () {
      const text = 'Some Shop\nTotal 25.00';
      final result = ReceiptParser().parse(text, linguaHint: 'en');
      expect(result.valuta, null);
    });
  });

  group('ReceiptParser.parse - robustness', () {
    test('garbage text with no signal -> isEmpty, no throw', () {
      const text = '!!!\n@@@\n###';
      final result = ReceiptParser().parse(text);
      expect(result.isEmpty, true);
    });

    test('empty string -> isEmpty, no throw', () {
      final result = ReceiptParser().parse('');
      expect(result.isEmpty, true);
    });

    test('default engine is mlkit', () {
      final result = ReceiptParser().parse('Bar Roma\nTotale € 12,50');
      expect(result.engine, OcrEngine.mlkit);
    });
  });
}
