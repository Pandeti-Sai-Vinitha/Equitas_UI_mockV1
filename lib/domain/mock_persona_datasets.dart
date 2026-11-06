import '../core/demo_config.dart';
import 'models.dart';

final mockPersonas = [
  // Persona 1: High Surplus -> Investment Target
  Persona(
    id: 'p_salaried_01',
    name: 'Ananya Sharma',
    occupation: 'Senior Software Engineer',
    type: PersonaType.salaried,
    avatarUrl: 'assets/avatars/salaried.png',
    financialSummary: FinancialSummary(
      currency: selectedDemoCurrency.code,
      currentBalance: selectedDemoCurrency.scaleAmount(185000),
      projectedIncome30D: selectedDemoCurrency.scaleAmount(120000),
      projectedSpend30D: selectedDemoCurrency.scaleAmount(65000),
      minimumBuffer: selectedDemoCurrency.scaleAmount(20000),
    ),
  ),

  // Persona 2: Cash Flow Gap / High Spend -> Loan/Credit Target
  Persona(
    id: 'p_biz_02',
    name: 'Rajesh Traders',
    occupation: 'Wholesale Electronics Merchant',
    type: PersonaType.business,
    avatarUrl: 'assets/avatars/business.png',
    financialSummary: FinancialSummary(
      currency: selectedDemoCurrency.code,
      currentBalance: selectedDemoCurrency.scaleAmount(45000),
      projectedIncome30D: selectedDemoCurrency.scaleAmount(210000),
      projectedSpend30D: selectedDemoCurrency.scaleAmount(310000),
      minimumBuffer: selectedDemoCurrency.scaleAmount(10000),
    ),
  ),
];
