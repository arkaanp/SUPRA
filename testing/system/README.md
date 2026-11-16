# Screenshot-based system testing

Evidence: `guidelines/system-test/notes.txt` and 21 user-supplied screenshots. Screenshots without related notes are accepted as implemented, as instructed by the user. This is a review of supplied manual evidence, not a new interactive app run.

**Nine scenario groups: 5 PASS, 3 PARTIAL, 1 FAIL.** Automated results remain 111 unit + 41 integration tests passed; screenshots are not added to that test total.

| ID | Scenario | Status | Outcome |
|---|---|---|---|
| ST-01 | Home: current/stale conditions, ML toggle and forecast strip | PASS | Figures 6.1-6.4; no note identifies a remaining change. |
| ST-02 | Profile and alert-preference controls | PASS | Figure 6.5; controls are accepted as implemented. |
| ST-03 | Saved places: map selection and saved list | PASS | Figures 6.6-6.8; saved Campus/Home entries are displayed. |
| ST-04 | Routine configuration, time selection and saved routine | PASS | Figures 6.9-6.13; creation and saved listing are accepted. Downstream use remains open in ST-05. |
| ST-05 | Alerts and routine consumption | PARTIAL | Figure 6.14 plus Home/routine evidence: current-trip alerts work; routine display and alert evaluation remain pending. |
| ST-06 | Assistant route/weather conversation | PARTIAL | Figure 6.15: a weather answer is displayed, but the notes report occasional irrelevant news/information. |
| ST-07 | Forgot-password email-to-reset journey | FAIL | Figure 6.16: email is sent, but its callback returns not_found instead of completing recovery. |
| ST-08 | Motorcycle/transit route display and trip UX | PARTIAL | Figures 6.17-6.19: routes and transit legs work; default metadata visibility and unavailable-data communication need changes. |
| ST-09 | Named route conditions, weather/air overlays and preview | PASS | Figures 6.20-6.21; no note identifies a remaining change. |

## Open changes from the notes

| ID | Area | Issue | Required change / retest |
|---|---|---|---|
| SYS-01 | Password recovery | Email is sent but the recovery callback returns not_found. | Complete the callback/reset-screen handoff. Retest from the recovery email through password update and sign-in. |
| SYS-02 | Assistant relevance | The assistant sometimes includes unrelated news or information. | Prioritize the question and current route/time; suppress unrelated reports. Retest rain/air/route questions with relevant and unrelated news available. |
| SYS-03 | Routine visibility | Saved routines are not displayed on Home or Alerts. | Surface enabled saved routines on both pages and refresh them after creation, edits and deletion. Verify days, departure time and endpoints. |
| SYS-04 | Routine alerts | Only the current trip is evaluated; routine evaluation is not yet included. | Evaluate enabled routines at their scheduled pre-departure window using routine/profile preferences. Retest due, disabled, non-due and opted-out routines. |
| SYS-05 | Trip metadata | OpenAQ metadata and provider details are exposed by default. | Collapse technical details by default behind an information control. Keep essential values and freshness visible and make source details available on demand. |
| SYS-06 | Transit unavailability | Public-transport data unavailability is not communicated clearly enough. | Show a clear unavailable-data state and actionable retry/alternative guidance. Distinguish unavailable service data from a returned itinerary with a missing fare. |

## Screenshot evidence

### Figure 6.1: ST-01 - PASS

Home in current/stale mode, with observed PM2.5, weather and pending forecast slots.

Source: `Screenshot From 2026-11-16 12-58-18.png`.

![Figure 6.1](<../../guidelines/system-test/Screenshot From 2026-11-16 12-58-18.png>)

### Figure 6.2: ST-01 - PASS

Home with PyTorch mode enabled and populated forecast hours.

Source: `Screenshot From 2026-11-16 12-58-44.png`.

![Figure 6.2](<../../guidelines/system-test/Screenshot From 2026-11-16 12-58-44.png>)

### Figure 6.3: ST-01 - PASS

Later ML forecast hours and model/source labels on Home.

Source: `Pasted image (3).png`.

![Figure 6.3](<../../guidelines/system-test/Pasted image (3).png>)

### Figure 6.4: ST-01 - PASS

Return to non-ML conditions mode and explicit pending/unavailable forecast values.

Source: `Pasted image (4).png`.

![Figure 6.4](<../../guidelines/system-test/Pasted image (4).png>)

### Figure 6.5: ST-02 - PASS

Profile settings and alert-preference switches, including the news-severity selector.

Source: `Pasted image (5).png`.

![Figure 6.5](<../../guidelines/system-test/Pasted image (5).png>)

### Figure 6.6: ST-03 - PASS

Saved-places empty state and the Save a place entry point.

Source: `Pasted image (6).png`.

![Figure 6.6](<../../guidelines/system-test/Pasted image (6).png>)

### Figure 6.7: ST-03 - PASS

Campus location selected on the map before saving.

Source: `Pasted image (7).png`.

![Figure 6.7](<../../guidelines/system-test/Pasted image (7).png>)

### Figure 6.8: ST-03 - PASS

Saved Campus and Home entries in the Places list.

Source: `Pasted image (8).png`.

![Figure 6.8](<../../guidelines/system-test/Pasted image (8).png>)

### Figure 6.9: ST-04 - PASS

Routine form with endpoints, travel mode, weekdays and pre-departure options.

Source: `Pasted image (9).png`.

![Figure 6.9](<../../guidelines/system-test/Pasted image (9).png>)

### Figure 6.10: ST-04 - PASS

Departure-time picker used to select 06:30.

Source: `Pasted image (10).png`.

![Figure 6.10](<../../guidelines/system-test/Pasted image (10).png>)

### Figure 6.11: ST-04 - PASS

Routine time and notification options after configuration.

Source: `Pasted image (11).png`.

![Figure 6.11](<../../guidelines/system-test/Pasted image (11).png>)

### Figure 6.12: ST-04 - PASS

Routine form and visible validation feedback; no additional defect is assigned beyond the notes.

Source: `Pasted image (12).png`.

![Figure 6.12](<../../guidelines/system-test/Pasted image (12).png>)

### Figure 6.13: ST-04 - PASS

Saved College weekday routine with its enabled weekday schedule. Home/Alerts consumption is tracked separately.

Source: `Pasted image (13).png`.

![Figure 6.13](<../../guidelines/system-test/Pasted image (13).png>)

### Figure 6.14: ST-05 - PARTIAL

Alerts inbox with current-trip subscriptions, publisher news, severity filtering and visible bulk controls. Routine coverage remains pending.

Source: `Pasted image (2).png`.

![Figure 6.14](<../../guidelines/system-test/Pasted image (2).png>)

### Figure 6.15: ST-06 - PARTIAL

Route/weather assistant reply that also includes general Jakarta accident news; relevance improvement is required.

Source: `Pasted image.png`.

![Figure 6.15](<../../guidelines/system-test/Pasted image.png>)

### Figure 6.16: ST-07 - FAIL

Recovery callback returns code not_found and Resource not found. Error-response excerpt; the browser callback query is excluded.

Source: `forgot-password.png`.

![Figure 6.16](<forgot-password-error-detail.png>)

### Figure 6.17: ST-08 - PARTIAL

Motorcycle route and environmental conditions; verbose provider metadata is still expanded on the route card.

Source: `Screenshot From 2026-11-16 13-06-51.png`.

![Figure 6.17](<../../guidelines/system-test/Screenshot From 2026-11-16 13-06-51.png>)

### Figure 6.18: ST-08 - PARTIAL

Blok M Hub and Plaza to Cibubur Transjakarta option, route overlay and technical metadata.

Source: `Pasted image (14).png`.

![Figure 6.18](<../../guidelines/system-test/Pasted image (14).png>)

### Figure 6.19: ST-08 - PARTIAL

Transit walking/ride legs and missing-fare label. Available itinerary display is implemented; unavailable-data messaging still requires a separate retest.

Source: `Pasted image (15).png`.

![Figure 6.19](<../../guidelines/system-test/Pasted image (15).png>)

### Figure 6.20: ST-09 - PASS

Named condition samples, category colors and expandable source/timestamp details along the route.

Source: `Pasted image (16).png`.

![Figure 6.20](<../../guidelines/system-test/Pasted image (16).png>)

### Figure 6.21: ST-09 - PASS

Start/destination condition cards, rain symbols and the active route-preview state.

Source: `Screenshot From 2026-11-16 13-09-09.png`.

![Figure 6.21](<../../guidelines/system-test/Screenshot From 2026-11-16 13-09-09.png>)

## Scope and follow-up

The six SYS items are open. Existing routine creation, map/condition views, forecast display, saved places and preference controls are accepted within the supplied evidence. Do not reopen historical backlog items solely because they appear in the older `guidelines/bugs-and-to-do.md` file.

Retest recovery from email to password reset; assistant answers against the current question/route; routine visibility and scheduled evaluation; default metadata disclosure; and explicit transit-unavailability states. Keep original screenshots and update notes/results after fixes. No application changes or new automated executions were made for this documentation update.
