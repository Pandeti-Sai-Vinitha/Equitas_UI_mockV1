# PLAN: AI Chat, Hive-Seeded Data, Latency & Demo Reset

Status: **Implemented (steps 1-7).** The sections below are the original plan; §14 records
what was built differently. Not yet checked on a physical device or emulator.

## 1. Goal

Turn the existing personalised home screen into a demo-ready retail banking mock that:

1. Loads persona data **from JSON into Hive** on first run, and treats Hive as the source of truth afterwards.
2. Provides a mock **AI Chat** that understands customer **intent** and **profile**, then either **recommends** (cross-sell) or **completes a task** (e.g. "Create an FD").
3. Simulates **network latency** on every mock API call, adjustable at demo time.
4. Supports a one-tap **demo reset** back to the JSON baseline.
5. Runs two scripted scenarios end to end (§9).

## 2. Out of scope

- A real LLM or Azure OpenAI integration (the chat engine goes behind an interface so one can be added later).
- A real backend, authentication, or HTTP networking.
- iOS/Android platform-specific work beyond what Flutter already provides.

## 3. Decisions needed before starting

| # | Question | Proposed default |
|---|---|---|
| D1 | `pubspec.yaml` requires Dart `^3.13.7`; the installed Flutter 3.41.2 ships Dart 3.11, so `pub get` and tests fail. | Lower the constraint to `^3.11.0` (no code in the project needs newer language features). Alternatively you upgrade Flutter. |
| D2 | Indian number formatting (`₹1,85,000`). | Small hand-written helper in `lib/core/format.dart`. **No new package.** (`intl` only if you approve it.) |
| D3 | The 7 non-compiling reference files in `lib/` (`load-json-to-state.dart`, `persona.dart`, `recommendation-rule.dart`, `recommendation-engine.dart`, `consuming-state-in-ui-widgets.dart`, `hive-with-riverpod-notifiers.dart`, `persisted-fd-notifier.dart`). | Move them to `docs/reference/` so they stay readable but leave the build and `flutter analyze` clean. `DemoControlPanelDrawer.dart` gets fixed and wired in (§7). |
| D4 | Chat entry point. | Floating "Ask AI" button on the home screen opening a full-screen chat; quick-action tiles also open chat with a pre-filled prompt. |
| D5 | Should activating the overdraft change Rajesh's balance? | Yes: it adds the sanctioned limit as "available credit" shown on the hero card; balance itself is unchanged. |

## 4. Fixes to existing behaviour

These are bugs found in review that block a clean demo:

| Fix | File |
|---|---|
| Filter the saved-FD list by the selected persona. | `riverpod-state-notifiers.dart`, `dynamic-home-canvas.dart` |
| Booking an FD debits the persona's balance in Hive; surplus and recommendations recompute. | new ledger logic (§5), `mock_api_routes.dart` |
| "Activate Overdraft Line" performs a real mock action (`POST /api/credit-lines`). | `mock_api_routes.dart`, home screen |
| Recommendations use their own metadata (tenor, payout) instead of hard-coded `12` / `atMaturity`; `AT_MATURITY`-style values map to the enum. | `fixed-deposit.dart`, home screen |
| Recommendation descriptions are built from live numbers, not hard-coded "₹2,20,000". | recommendation engine (§5.4) |
| Quick-action tiles become tappable (open chat with that intent). | home screen |
| Remove the duplicated `computedMetrics` block from persona JSON (the app computes these). | persona JSON files |

## 5. Data layer: JSON → Hive

### 5.1 Richer persona data (JSON)

Extend each persona file so the chat has something to personalise from. Existing fields are kept.

```jsonc
{
  "persona": { ... },                    // unchanged
  "financialSummary": { ... },           // unchanged minus computedMetrics
  "contextualTriggers": { ... },         // unchanged; microActions gain an "intent" key
  "spendByCategory": [                   // NEW — last 30 days
    { "category": "RENT", "amount": 28500 },
    { "category": "DINING", "amount": 9200 }
  ],
  "recentTransactions": [                // NEW — ~10 rows
    { "id": "t1", "date": "2026-10-28", "description": "Salary credit", "amount": 120000, "type": "CREDIT", "category": "INCOME" }
  ],
  "holdings": [],                        // NEW — existing products (FDs, credit lines); drives eligibility
  "goals": [ { "name": "Emergency fund", "target": 300000 } ]   // NEW, optional
}
```

### 5.2 Hive boxes

| Box | Key → value | Notes |
|---|---|---|
| `settingsBox` | `selected_persona_id`, `seed_version`, `latency_ms`, `demo_settings` | existing box, new keys |
| `personasBox` | personaId → full persona JSON map | **new**; seeded from JSON |
| `transactionsBox` | bookingId → FD booking map | existing; name kept for compatibility |
| `creditLinesBox` | id → credit-line map | **new** |
| `chatBox` | personaId → list of chat message maps | **new**; history per persona |

### 5.3 Seeding

New `DataSeeder` (`lib/data/data_seeder.dart`):

- On startup: if `settingsBox['seed_version']` is missing or older than `kSeedVersion`, read every persona JSON asset and write it to `personasBox`.
- `reseed()` clears all boxes and seeds again (used by demo reset).
- Mock routes read and write `personasBox` instead of `rootBundle`.

### 5.4 Recommendation engine (computed, not static)

`lib/domain/recommendation_engine.dart` — ports the orphaned rule logic and adds eligibility:

| Condition | Recommendation |
|---|---|
| Surplus > ₹10,000 and no active FD for this amount | FD for 70% of surplus, rounded to ₹5,000; rate from `recommendations_rules.json` product catalogue |
| Deficit > 0, business persona, no active credit line | Merchant overdraft for deficit + 15,000 buffer |
| Deficit > 0, salaried persona | Pre-approved personal loan |
| Dining/shopping share > threshold | (Optional) rewards credit card cross-sell |

`recommendations_rules.json` becomes a **product catalogue** (rates, min/max tenors, fees); amounts and wording come from the engine.

## 6. Mock API & latency

### 6.1 `MockApiClient`

Replace direct static calls with an injectable client (Riverpod provider) so latency, failures and test fakes can be swapped in:

```dart
abstract interface class ApiClient {
  Future<Map<String, dynamic>> get(String path);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body);
}
```

`MockApiClient` wraps `MockApiRoutes.dispatch` and, per call:

- waits `latencyMs ± 20% jitter` (from `DemoSettings`);
- optionally fails a call if "Simulate failure" is switched on (demonstrates error states);
- per-route overrides, e.g. chat responses use a "thinking" delay of 800–1500 ms.

The hard-coded `Future.delayed(2s)` in `FDBookingNotifier` is removed.

### 6.2 Routes (all return `{status, data}`)

| Method | Path | Change |
|---|---|---|
| GET | `/api/personas` | now reads `personasBox` |
| GET | `/api/personas/{id}` | now reads `personasBox` |
| GET | `/api/personas/{id}/transactions` | **new** |
| GET | `/api/recommendations/{id}` | **now computed** by the engine |
| GET | `/api/fd-bookings?personaId=` | **new** — persona-filtered list |
| POST | `/api/fd-bookings` | **now debits balance** and checks sufficient funds |
| POST | `/api/credit-lines` | **new** — activates overdraft/loan |
| POST | `/api/chat` | **new** — `{personaId, message, pendingAction?}` → chat reply |
| POST | `/api/demo/reset` | **new** — calls `DataSeeder.reseed()` |

Validation errors become a typed `MockApiException(code, message)` in `lib/core/exceptions.dart` (Dart equivalent of the `AppError` pattern in `CLAUDE.md`) and are rendered as friendly messages.

## 7. Demo control panel & reset

Fix and wire the existing `DemoControlPanelDrawer`:

- Attach as `endDrawer` on the home screen (opened from a tune icon in the app bar).
- Fix compile errors (`Colors.sky`, missing imports, deprecated `withOpacity`).
- Controls: persona picker, latency slider (0–3000 ms, persisted), "Simulate failure" switch, counts of stored FDs / credit lines / chat messages.
- **Reset Demo to Baseline**: `POST /api/demo/reset` → `ref.invalidate(...)` on persona, recommendations, bookings, credit lines and chat providers → snackbar. After reset the UI matches a fresh install with no restart.
- Optional hidden shortcut: long-press the avatar to reset (useful mid-presentation).

## 8. AI Chat (mock)

### 8.1 Architecture

```
ChatScreen ──▶ ChatNotifier ──▶ ApiClient.post('/api/chat')
                                   │
                                   ▼
                          RuleBasedChatEngine  (implements ChatEngine)
                           ├─ IntentClassifier   (keywords + regex, scored)
                           ├─ SlotExtractor      (amount, tenor, payee)
                           ├─ ProfileContext     (persona + summary + spend + holdings)
                           └─ ResponseComposer   (text + optional action card)
```

`ChatEngine` is an interface (composition, per `CLAUDE.md`), so an LLM-backed engine can replace the rule-based one later without touching UI or notifiers.

### 8.2 Intents

| Intent | Example utterances | Response |
|---|---|---|
| `CHECK_BALANCE` | "what's my balance", "how much do I have" | Balance + 30-day projection |
| `SPEND_INSIGHT` | "where is my money going", "how much on dining" | Top categories, comparison to income |
| `SURPLUS_ADVICE` / `RECOMMEND` | "I have extra money", "what should I do with my savings" | Profile-based cross-sell (FD for surplus persona) |
| `CREATE_FD` | "create an FD of 1 lakh for 12 months", "open fixed deposit" | Slot-fill missing amount/tenor → confirmation card → booking |
| `NEED_CREDIT` | "can I pay my supplier", "I'm short on cash" | Detects deficit → offers overdraft/loan → activation card |
| `PAY_BILL` | "pay rent", "pay landlord" | Mock payment confirmation card (debits balance) |
| `LOCK_CARD` | "lock my card" | Confirmation card → status change |
| `SMALL_TALK` / `HELP` | "hi", "what can you do" | Greeting + suggested prompts |
| `FALLBACK` | anything else | "I didn't catch that" + suggestions |

### 8.3 Slot extraction

- Amounts: `150000`, `1,50,000`, `1.5 lakh`, `1L`, `50k`, `₹2 lakhs`.
- Tenor: `12 months`, `1 year`, `18m`, `2 yrs`.
- Missing slots trigger a follow-up question; defaults come from the recommendation (shown as quick-reply chips, e.g. "₹1.5L recommended").
- Guard rails: amount greater than (balance − buffer) → assistant warns and suggests the safe maximum.

### 8.4 Conversation state

- `ChatState { messages, isTyping, pendingAction }`; `pendingAction` holds a half-filled task (e.g. FD awaiting tenor).
- Confirming an action card calls the same booking/credit-line routes the home screen uses, so both views stay in sync.
- History persisted per persona in `chatBox`; switching persona switches conversation; reset clears it.

### 8.5 UI

- Message bubbles, typing indicator (driven by simulated latency), suggestion chips under the input, and rich **action cards** (FD summary with amount / tenor / rate / maturity and Confirm / Edit buttons).
- Persona-aware greeting: "Hi Ananya — your salary just cleared and you have ₹2.2L you won't need this month."

## 9. Demo scenarios (acceptance criteria)

### Scenario 1 — Ananya (salaried, surplus): recommend → complete task

1. App opens on Ananya; hero shows "PAYCHECK CLEARED"; FD recommendation visible.
2. Tap **Ask AI** → greeting references her surplus.
3. "I have some extra money this month" → assistant recommends FD of ₹1.5L @ 7.2% with maturity amount.
4. "Create an FD of 1 lakh" → assistant asks tenor (chips: 6 / 12 / 24 months).
5. Tap "12 months" → confirmation card → **Confirm** → typing delay → success with FD ID.
6. Back on home: balance reduced by ₹1L, booking listed, recommendation amount recomputed.

### Scenario 2 — Rajesh (business, deficit): detect gap → cross-sell credit

1. Switch to Rajesh; hero shows "MERCHANT SETTLEMENT DUE"; liquidity-gap warning visible; no Ananya bookings shown.
2. "Can I pay my electronics supplier this week?" → assistant explains the ₹65K gap from projected payables.
3. Assistant offers pre-approved ₹80K overdraft @ 11.5%, zero processing fee → activation card.
4. **Activate** → success; hero shows available credit; recommendation disappears.

### Reset

- Open demo panel → **Reset Demo to Baseline** → both personas return to JSON values, no bookings, no credit lines, empty chats, Ananya selected. No app restart.

## 10. File plan

```
lib/
  core/        exceptions.dart, format.dart (INR), latency.dart
  data/        data_seeder.dart, hive_boxes.dart, api_client.dart, mock_api_client.dart
  routes/      mock_api_routes.dart            (extended)
  domain/      models.dart, fixed_deposit.dart, credit_line.dart, recommendation_engine.dart
  chat/        chat_models.dart, chat_engine.dart, rule_based_chat_engine.dart,
               intent_classifier.dart, slot_extractor.dart, response_composer.dart
  state/       persona_notifier.dart, booking_notifier.dart, credit_line_notifier.dart,
               chat_notifier.dart, demo_settings_notifier.dart
  screens/     dynamic-home-canvas.dart (updated), chat_screen.dart
  widgets/     demo_control_panel_drawer.dart, chat_bubble.dart, action_card.dart
docs/reference/  (orphaned sample files moved here — D3)
```

Existing files move into this layout with their logic intact; imports updated in one step. (No files under `internal/deprecated/` are touched.)

## 11. Testing (target ≥ 80% line coverage, `flutter test --coverage`)

| Test file | Covers |
|---|---|
| `test/data/data_seeder_test.dart` | first-run seed, no re-seed on same version, reseed clears everything |
| `test/routes/mock_api_routes_test.dart` | every route, FD debit, insufficient funds, persona filtering, credit line, reset |
| `test/data/mock_api_client_test.dart` | latency applied (fake clock), failure injection |
| `test/domain/recommendation_engine_test.dart` | surplus → FD, deficit → overdraft/loan, eligibility after holding exists |
| `test/chat/intent_classifier_test.dart` | table-driven utterance → intent for every intent + fallback |
| `test/chat/slot_extractor_test.dart` | all amount/tenor formats |
| `test/chat/rule_based_chat_engine_test.dart` | multi-turn slot filling, guard rails |
| `test/state/*_test.dart` | notifiers with `ProviderContainer` overrides |
| `test/widgets/home_test.dart`, `chat_screen_test.dart` | both scenarios as widget tests, reset flow |

Existing tests in `test/widget_test.dart` are kept and updated to the new Hive-backed routes.

## 12. Delivery order

1. **Housekeeping** — D1 SDK constraint, D3 move orphans, get `flutter analyze` + existing tests green.
2. **Data layer** — richer JSON, seeder, Hive-backed routes, `ApiClient` + latency.
3. **Bug fixes & engine** — §4 fixes, computed recommendations, credit-line route.
4. **Demo panel & reset**.
5. **Chat engine** (no UI) with full unit tests.
6. **Chat UI** + action cards + home-screen entry points.
7. **Scenario widget tests**, coverage check, README update.

Each step ends with `flutter analyze` and `flutter test` passing.

## 13. Risks

- **Rule-based intent matching is brittle** off-script. Mitigation: suggestion chips steer presenters; fallback reply always offers the scripted prompts.
- **Hive schema changes** between builds. Mitigation: `seed_version` triggers a clean reseed.
- **SDK mismatch (D1)** blocks everything until resolved.

## 14. Outcome and deviations

### Delivery status

| # | Step | Status |
|---|---|---|
| 1 | Housekeeping (SDK constraint, orphan files, analyzer clean) | Done |
| 2 | Data layer: richer JSON, Hive seeder, Hive-backed routes, `ApiClient` + latency | Done |
| 3 | Bug fixes and computed recommendations, credit-line route | Done |
| 4 | Demo panel and reset | Done |
| 5 | Chat engine with unit tests | Done |
| 6 | Chat UI, action cards, home-screen entry points | Done |
| 7 | Scenario tests, coverage check, README, demo script | Done: see `DEMO.md` |

### Decisions (§3), as resolved

| # | Decision |
|---|---|
| D1 | Dart constraint lowered to `^3.11.0`. |
| D2 | Hand-written `formatInr` in `lib/core/format.dart`; no new package. |
| D3 | Non-compiling samples moved to `docs/reference/`, excluded from analysis. |
| D4 | "Ask AI" floating button; quick-action tiles open the chat with their prompt. |
| D5 | Activating the overdraft shows available credit on the hero card; the balance is unchanged until it is drawn on. |

### Deviations from the plan

- **No `creditLinesBox`.** Credit lines and loans are stored as holdings on the persona record, next to the balance they affect. The demo reset already clears them.
- **No `POST /api/demo/reset` route.** Reset is a presenter control: `demoResetProvider` talks to the seeder directly so it works while "simulate failure" is on and ignores simulated latency. Latency and failure settings survive a reset.
- **Extra routes:** `POST /api/payments` and `POST /api/cards/lock` (needed for the pay-bill and lock-card chat intents), and `GET /api/fd-bookings?personaId=`.
- **Overdraft draws:** an active overdraft line can be drawn on for payments, taking the balance below zero (payroll in Scenario 2 relies on this).
- **Chat latency:** replies wait 0.8-1.5 s even on a fast simulated network; a slower network wins; latency 0 turns it off.
- **Cards confirm by text.** Confirm / Cancel send "Yes, go ahead" / "No, cancel", so the engine handles buttons and typed replies the same way.
- **Recommendations** moved into `product_catalogue.json` (rates, segments, sizing rules, wording templates). `recommendations_rules.json` was removed.
- **Testing approach:** Hive file IO never completes inside a widget test's fake clock, so screens are tested with in-memory storage and assets (`test/helpers/widget_harness.dart`); Hive itself is covered by unit tests against a temp folder.

### Verification

- `flutter analyze`: no issues. `flutter test --coverage`: 253 tests pass; 98.6% of lines (2,008 of 2,037). The uncovered lines are `main()` and the `ApiClient` interface file.
- Both demo scenarios and the reset run end to end through the real screens in `test/screens/app_flows_test.dart`.
- **Not verified:** behaviour on a device or emulator (layout at the demo screen width, feel of the simulated latency).

### Known limits

- The mock "AI" is keyword and regex based. Off-script wording falls back to a help message with suggested prompts; the demo script lists wording that is known to work.
- Money uses `double`, which is fine for a mock but not for real banking.
- FD interest is simple interest, not compounded.
- Only the debit-card lock exists; there is no unlock.
