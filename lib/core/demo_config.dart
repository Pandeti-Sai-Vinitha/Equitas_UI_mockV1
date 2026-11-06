import 'demo_currency.dart';
import 'demo_template.dart';

// Configure both the demo currency and appearance here.
const selectedDemoCurrency = DemoCurrency.inr;
const selectedDemoTemplate = DemoTemplate.dark;
const demoMpin = '1234';

class DemoLoginAccount {
  final String email;
  final String password;
  final String personaId;

  const DemoLoginAccount({
    required this.email,
    required this.password,
    required this.personaId,
  });
}

// Demo-only credentials; this client-side mapping is not production auth.
const demoLoginAccounts = <DemoLoginAccount>[
  DemoLoginAccount(
    email: 'ananya.sharma@gmail.com',
    password: 'ananya123',
    personaId: 'p_salaried_01',
  ),
  DemoLoginAccount(
    email: 'rajesh.traders@gmail.com',
    password: 'rajesh123',
    personaId: 'p_biz_02',
  ),
];

const selectedDemoColors = selectedDemoTemplate == DemoTemplate.light
    ? DemoTemplateColors.light
    : DemoTemplateColors.dark;
