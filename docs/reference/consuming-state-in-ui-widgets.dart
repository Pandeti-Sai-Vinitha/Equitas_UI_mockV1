import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personaState = ref.watch(personaProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final bookingState = ref.watch(fdBookingProvider);

    final currentPersona = personaState.selectedPersona;
    final summary = currentPersona.financialSummary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank AI Advisory POC'),
        actions: [
          // Persona Switcher Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DropdownButton<String>(
              value: currentPersona.id,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: personaState.personas.map((p) {
                return DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) {
                  ref.read(personaProvider.notifier).selectPersona(id);
                  ref.read(fdBookingProvider.notifier).reset(); // Reset booking state on switch
                }
              },
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Balance Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(currentPersona.occupation, style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Text('Current Balance: ₹${summary.currentBalance.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('30D Inflow: ₹${summary.projectedIncome30D.toStringAsFixed(0)}'),
                        Text('30D Spend: ₹${summary.projectedSpend30D.toStringAsFixed(0)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Dynamic Product Recommendations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Recommendations List
            ...recommendations.map((rec) {
              return Card(
                color: rec.category == ProductCategory.investment ? Colors.green[50] : Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rec.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(rec.description),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(rec.actionType == ActionType.openFD ? 'Book FD Now' : 'Check Loan Offer'),
                        onPressed: bookingState.status == FDBookingStatus.loading
                            ? null
                            : () {
                                // Trigger FD Booking execution
                                ref.read(fdBookingProvider.notifier).bookFixedDeposit(
                                      personaId: currentPersona.id,
                                      depositAmount: rec.recommendedAmount,
                                      tenorMonths: 12,
                                      interestRate: rec.expectedReturnOrInterestRate,
                                      payoutOption: InterestPayout.atMaturity,
                                      autoRenew: true,
                                    );
                              },
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            // Booking Result Feedback Banner
            if (bookingState.status == FDBookingStatus.loading)
              const Center(child: CircularProgressIndicator())
            else if (bookingState.status == FDBookingStatus.success)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.green[100],
                child: Text(
                  'Success! Booking ID: ${bookingState.bookingResult?.id} | Maturity Amt: ₹${bookingState.bookingResult?.maturityAmount.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold),
                ),
              )
            else if (bookingState.status == FDBookingStatus.error)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red[100],
                child: Text(bookingState.errorMessage ?? 'Error occurred', style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}