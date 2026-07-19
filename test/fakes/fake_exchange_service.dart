import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';

/// Widget-test double: fixed [rate] (null → simulate offline/unsupported),
/// counts calls. Never touches SharedPreferences or the network.
class FakeExchangeService extends ExchangeService {
  FakeExchangeService({this.rate}) : super(SettingsService());

  double? rate;
  int calls = 0;

  @override
  Future<ExchangeResult?> convert({
    required double amount,
    required String from,
    required DateTime date,
  }) async {
    calls++;
    final r = rate;
    return r == null ? null : ExchangeResult(amountEur: amount * r, rate: r);
  }
}
