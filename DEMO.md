# Demo script

Two personas, two scenarios, about five minutes. Every prompt below is covered by a test
(`test/screens/app_flows_test.dart` for the two main scenarios, `test/chat/` for the
extras), so the replies shown are what the engine produces. It has not been walked through on a device.

## Before you start

1. `flutter run` on the screen size you will present on.
2. Sign in with Ananya's demo account: `ananya.sharma@gmail.com` / `ananya123`.
3. Reset to a clean state: tap the **tune icon** (top right) → **Reset Demo to Baseline**. (Shortcut: long-press the avatar, top left.)
4. Optional: in the same panel, set **Simulated Delay** to about 600-1000 ms so the network feels real. Chat replies always wait 0.8-1.5 s.
5. Confirm chat actions with the demo MPIN `1234` (configurable in `lib/core/demo_config.dart`).

Starting position: Ananya Sharma, balance **₹1,85,000**, offer "High-Yield Fixed Deposit".

## Scenario 1: Ananya (salaried, has spare cash) — recommend, then do the task

| # | You do | What the audience sees |
|---|---|---|
| 1 | Sign in as Ananya | "PAYCHECK CLEARED" hero, balance ₹1,85,000, an FD offer sized from her cash flow (₹1,50,000 at 7.2%), spend and income summary |
| 2 | Tap **Ask AI** | The assistant greets her by name: ₹2,20,000 free after bills and her ₹20,000 safety buffer |
| 3 | Tap the chip **I have some extra money this month** | Recommendation: FD of ₹1,50,000 at 7.2% for 12 months, grows to ₹1,60,800, balance would still be ₹35,000 |
| 4 | Tap the chip **Create an FD of ₹1,50,000 for 12 months** | A confirmation card: amount, tenor, rate, payout, auto-renew, maturity, balance after |
| 5 | Tap **Confirm FD** | "Working…", then "Done! Your fixed deposit FD_… is booked… matures on <date>" and the card turns **Done** |
| 6 | Tap back | Balance is now **₹35,000**, the FD is listed under "SAVED FD BOOKINGS", and the offer has shrunk to ₹45,000 |

Extras if there is time (type them):

- **Where is my money going?** → Rent ₹28,500 (44%), Dining ₹9,400 (14%), Groceries ₹8,200 (13%), 54% of her income.
- **Create an FD of 1 lakh** → the assistant asks for the tenor with chips (6 / 12 / 24 months).
- **Create an FD of 1.8 lakh for 12 months** → warns it would dip into her safety buffer and suggests ₹1,65,000.
- **Pay my house rent** → payee and amount (₹28,500) come from her last rent payment.
- **Lock my debit card** → card, confirm, and the home screen shows "Card locked".

## Scenario 2: Rajesh (business, short on cash) — detect the gap, cross-sell credit

| # | You do | What the audience sees |
|---|---|---|
| 1 | Log out, then sign in as `rajesh.traders@gmail.com` / `rajesh123` | Rajesh Traders, "MERCHANT SETTLEMENT DUE", balance ₹45,000, a liquidity-gap warning with a **Merchant Overdraft Line**; no FDs from the other persona |
| 2 | Tap the **Vendor Payout** tile | The chat opens with "Can I pay my electronics supplier this week?" already sent |
| 3 | Read the reply | About ₹65,000 short over 30 days; offers a ₹80,000 pre-approved overdraft at 11.5% with nil processing fee, as a card |
| 4 | Tap **Activate** | "Done! Your overdraft line of ₹80,000 is active…" |
| 5 | Type **Approve payroll for my 12 employees** | Payment card for ₹54,000 to "Payroll - 12 employees"; it shows **₹9,000 from overdraft** because payroll is more than his balance |
| 6 | Tap **Pay now** | "Paid ₹54,000… your balance is now -₹9,000 (₹9,000 is drawn from your overdraft)" |
| 7 | Tap back | Hero shows **-₹9,000** and "+ ₹80,000 overdraft available"; the overdraft offer is gone |

Extra: tap the **GST Tax Reserve** tile → "You spent ₹12,000 on GST this month, 4% of your total spend."

## Showing the mock network and resilience

- **Latency:** drag the slider in the demo panel to 2-3 s and ask anything; the typing indicator stays up for that long.
- **Failure:** switch on **Simulate Failure**, send any message → an error bubble with a **Try again** chip. Switch it off and tap the chip; the last message is resent.

## Resetting between runs

Tune icon → **Reset Demo to Baseline** (or long-press the avatar). Both personas return to their JSON values, FDs, credit lines and chat history are cleared, and Ananya is selected. No restart needed. Your latency and failure settings are kept.

## Wording that works

The assistant is rule-based, so stay close to these ideas:

| Ask about | Examples |
|---|---|
| Balance | "What's my balance?", "How much do I have?" |
| Spending | "Where is my money going?", "How much do I spend on dining?" |
| Spare money | "I have some extra money this month", "What should I do with my savings?" |
| An FD | "Create an FD of 1 lakh", "Open a fixed deposit for 12 months" (amounts like `1.5 lakh`, `50k`, `₹1,50,000`; tenors like `12 months`, `2 years`) |
| Credit | "Can I pay my supplier this week?", "I'm short on cash", "Can I cover my upcoming payments?" |
| Payments | "Pay my house rent", "Approve payroll for my 12 employees", "Send money to my landlord" |
| Card | "Lock my debit card" |

Anything else gets a polite "I didn't quite catch that" with suggested prompts, so a mistyped
question never dead-ends. Confirm with the card buttons or by typing "yes"; decline with
"no" or "cancel".
