# SafePlate Test Traceability

## Test approach

No automated test runner is configured yet. This file implements manual acceptance
tests for every implemented user story and formal acceptance criterion. Run them
against production or a local build. Create an inspector, an owner with a linked
store, and a second owner to check data isolation. Use unique test emails.

## Production code map

| Area | Production code |
| --- | --- |
| Registration and role routing | `src/components/auth/register-form.tsx`, `src/lib/auth.ts`, `supabase/schema.sql` |
| Sign in and sign out | `src/components/auth/login-form.tsx`, `src/components/dashboard/workspace.tsx` |
| Store ownership and selection | `src/components/dashboard/store-link-form.tsx`, `src/app/inspector/page.tsx` |
| Checklist and evidence | `src/components/dashboard/inspection-checklist.tsx`, `supabase/schema.sql` |
| Tickets and notifications | `src/app/owner/page.tsx`, `src/components/dashboard/workspace.tsx`, `supabase/schema.sql` |
| Ticket evidence submission | `src/app/owner/tickets/[ticketId]/page.tsx`, `src/components/dashboard/evidence-upload-form.tsx`, `supabase/migrations/20261114000000_ticket_evidence.sql` |
| Remediation deadlines and priorities | `src/lib/deadlines.ts`, `src/components/dashboard/deadline-badge.tsx`, `src/components/dashboard/workspace.tsx`, `src/app/owner/tickets/[ticketId]/page.tsx` |
| Evidence review | `src/app/inspector/page.tsx`, `src/components/dashboard/evidence-review-queue.tsx`, `src/components/dashboard/review-decision-form.tsx`, `src/components/dashboard/item-status.tsx`, `supabase/migrations/20261116000000_review_ticket_evidence.sql` |

## Account and access

### Story 1: Register with a role

**Production code:** The registration form sends the selected role to Supabase Auth;
the profile trigger creates the matching `profiles` record.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-1.1 | Register one new F&B inspector and one new store owner. Sign in with both accounts. | The inspector reaches `/inspector`; the owner reaches `/owner`; each sees only their role's workspace. |

### Story 2: Secure login

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC2.1 Successful login | `signInWithPassword` authenticates and redirects based on the database profile role. | **MAN-2.1:** Sign in with valid inspector credentials, then valid owner credentials. | Each account is authenticated and reaches the correct dashboard. |
| AC2.2 Incorrect password | Authentication errors retain the user on the sign-in page. | **MAN-2.2:** Use a valid registered email with a wrong password. | No login occurs and “Invalid email or password” is displayed. |
| AC2.3 Malicious username / SQL injection | Email format validation rejects malformed input before authentication; Supabase Auth does not interpolate SQL. | **MAN-2.3:** Enter `' OR 1=1 --` as the email and any password. | No login occurs and “Enter a valid email address and password” is displayed. |

### Navigation behavior

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-NAV-1 | While signed in, select **Sign out**. | The session ends and the user lands on `/`, the sign-in page. |
| MAN-NAV-2 | Open `/` while signed out, then select **Create an account**. | `/` is a sign-in page and registration opens at `/register`. |

## Store ownership and opening an inspection

### Story 3: Link a store to its owner

**Production code:** `StoreLinkForm` inserts a store for the authenticated owner;
store RLS policies restrict each owner to their own records.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-3.1 | Owner A links “Owner A Test Cafe”. Sign out and sign in as Owner B. | Owner A sees the store; Owner B cannot view or manage it. |

### Story 4: Inspector selects a store and opens a checklist

**Production code:** The inspector page loads stores and passes them to
`InspectionChecklist`.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-4.1 | After Owner A links a store, sign in as an inspector and select “Owner A Test Cafe”. | The store appears in the selector and its digital checklist opens. |

## Conducting an inspection

### Story 5: Mark items pass or fail

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC5.1 Mark pass | The checklist stores `result: "pass"` without evidence requirements. | **MAN-5.1:** Mark an unmarked item **Pass**. | The item is shown as passed; no comment or photo is required. |
| AC5.2 Mark fail | Failed state reveals evidence and deadline controls. | **MAN-5.2:** Mark an unmarked item **Fail**. | Comment, photo, and remediation-deadline controls are shown. |
| AC5.3 Submit with unmarked item | The checklist calculates `unmarkedItems` before inserting an inspection. | **MAN-5.3:** Leave one item unmarked and submit. | Submission is rejected and names the unmarked item. |

### Story 6: Required comment for a flagged item

**Production code:** Both the browser and the ticket trigger reject failed items
without a comment.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-6.1 | Mark an item fail, leave its comment blank, set a deadline, complete all remaining items, and submit. | Submission is rejected and identifies the failed item needing a comment. |

### Story 7: Attach photo evidence

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| Successful attachment | Allowed images upload to the private bucket and `photo_path` is saved with the failed item. | **MAN-7.1:** Add a comment, future deadline, and small JPG/PNG/WebP to a failed item; complete and submit. Sign in as the linked owner. | The owner ticket has **View inspection photo**, which opens the evidence. |
| Unsupported file type | The form rejects types other than JPEG, PNG, and WebP; bucket restrictions provide a second check. | **MAN-7.2:** Attempt to attach a TXT or PDF file to a failed item. | The upload is rejected and accepted formats are stated. |

### Story 8: Remediation deadline

**Production code:** A failed item needs a deadline of today or later; client and
database trigger both enforce this.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-8.1 | Add a future deadline to a failed item, complete the inspection, and submit. | The deadline is accepted and shown on the owner ticket as “Fix by.” |
| MAN-8.2 | Leave the deadline blank for a failed item, complete the other items, and submit. | Submission is rejected and identifies the item requiring a deadline. |
| MAN-8.3 | Repeat MAN-8.2 using a past deadline. | Submission is rejected and asks for today or a later date. |

### Story 9: Submit an inspection and generate a ticket

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC9.1 All-pass submission | `create_remediation_ticket` aggregates only failed items. | **MAN-9.1:** Mark every item pass and submit, then sign in as the owner. | The inspection is saved as passed and no ticket appears. |
| AC9.2 Failed submission | The trigger creates one owner ticket containing every failed item. | **MAN-9.2:** Submit two failed items, each with comment and future deadline; sign in as the linked owner. | One ticket appears with both items, comments, and deadlines. |
| AC9.3 Missing deadline | Browser and trigger both reject a failed item without a deadline. | **MAN-9.3:** Fail an item, add a comment but no deadline, then submit. | Submission is rejected and asks the inspector to set a deadline. |

## Receiving and responding to a ticket

### Story 10: Receive a notification

**Production code:** `create_ticket_notification` inserts an owner-scoped
notification after `create_remediation_ticket`; owner RLS controls visibility.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-10.1 | Submit an inspection with at least one valid failed item for Owner A’s store. Sign in as Owner A, then Owner B. | Owner A sees “New inspection ticket” and the ticket. Owner B sees neither. |

### Story 11: View comments and photos

**Production code:** The owner page creates short-lived signed URLs after an
owner-scoped ticket query. Storage RLS permits only a ticket’s owner to read its
referenced photo.

| Test ID | Manual test case | Expected result |
| --- | --- | --- |
| MAN-11.1 | Sign in as the linked owner for the ticket created in MAN-7.1. | Every failed item shows its comment and deadline; the evidence item has a working photo link. |
| MAN-11.2 | Sign in as a different owner and attempt to access the first owner’s ticket/evidence through normal app navigation. | The other owner cannot view the ticket or photo. |

### Story 12: Upload evidence that a flagged issue is fixed

**Production code:** The owner opens a ticket at `/owner/tickets/[ticketId]` and
uploads a photo per flagged item to the private `remediation-evidence` bucket
(path `<owner id>/<ticket id>/<file>`). `submit_ticket_evidence` checks ticket
ownership, attaches the evidence to the flagged item, sets its status to
`pending_inspector_review` and sets `resolved_late` when the deadline has passed.
Storage RLS only lets the ticket's owner upload, and lets the issuing inspector read.

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC12.1 Evidence before deadline | The photo is uploaded, then `submit_ticket_evidence` stores `evidence_photo_path` on the item and sets `status: "pending_inspector_review"`. | **MAN-12.1:** As Owner A, open a ticket with a future deadline via **Upload evidence of fixes**, choose a JPG/PNG/WebP photo for one item, and select **Submit for inspector review**. | The item shows **Pending inspector review** and **View submitted evidence** opens the photo. No email is needed. |
| AC12.2 Evidence after deadline | The function still accepts the submission and sets `resolved_late: true` when today is after the item's deadline. | **MAN-12.2:** In the Supabase SQL editor, move one flagged item's `remediation_deadline` on Owner A's open ticket to a past date. As Owner A, submit evidence for that item. | The submission is accepted; the item shows **Pending inspector review** and **Resolved late**. A warning shows before submission. |
| AC12.3 Non-owner submission | RLS hides the ticket from other owners; the page shows an authorization error. Storage RLS and the function (`42501`) reject uploads and submissions from non-owners. | **MAN-12.3:** Copy the URL of Owner A's ticket page. Sign in as Owner B (Store B) and open that URL. Optionally, in the browser console, call `submit_ticket_evidence` with Owner A's ticket ID. | Owner B sees **Not authorized** with “You are not authorized to submit evidence for this ticket.” The RPC call is rejected and nothing changes on Owner A's ticket. |
| Unsupported file type | The form accepts only JPEG, PNG and WebP up to 5 MB; the bucket enforces the same limits. | **MAN-12.4:** Choose a PDF or TXT file as evidence. | The file is rejected and the accepted formats are stated. |

### Story 13: See the remediation deadline for each issue

**Production code:** `DeadlineBadge` shows each flagged item's deadline as a
readable date with a countdown worked out from the owner's own local date, so
“Due today” is right in the owner's timezone. `sortByDeadline` orders items
needing action by earliest deadline; items with submitted evidence come last.
The **Fix priorities** card lists every outstanding item across open tickets.

No formal acceptance criteria were supplied with this story; these were derived from it.

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC13.1 Deadline on every issue | Each flagged item on the dashboard and ticket page shows **Fix by:** with the formatted date and a countdown. | **MAN-13.1:** As Owner A, open the workspace and a ticket page for a ticket with two failed items. | Every item shows its deadline (e.g. “Fix by: Fri, Nov 20, 2026 · Due in 5 days”). |
| AC13.2 Prioritized by deadline | **Fix priorities** lists outstanding items from all open tickets, earliest deadline first. Ticket items are sorted the same way. | **MAN-13.2:** Create two tickets for Owner A whose items have different deadlines (e.g. +7 days and +1 day). Open the workspace. | The +1 day item appears first in **Fix priorities** and first within its ticket. |
| AC13.3 Urgency is clear | Overdue and due-today items are red, items due within 3 days are amber, later items are neutral. | **MAN-13.3:** In the Supabase SQL editor, set one item's deadline to today, one to tomorrow and one to a past date. Reload the workspace. | Labels read “Due today” (red), “Due tomorrow” (amber) and “Overdue by N days” (red). The overdue item is listed first. |
| AC13.4 Submitted items drop off the list | Items with evidence submitted leave **Fix priorities** and show “Evidence submitted” instead of a countdown. | **MAN-13.4:** Submit evidence for one item (MAN-12.1) and return to the workspace. | That item is no longer in **Fix priorities**; on its ticket it shows “Evidence submitted” and is listed after outstanding items. |
| Data isolation | Deadlines come from the owner-scoped ticket query (RLS). | **MAN-13.5:** Sign in as Owner B. | Owner B sees none of Owner A's deadlines or priorities. |

### Story 14: Review evidence submitted by a store owner

**Production code:** The inspector workspace shows **Evidence to review**: every
flagged item on the inspector's own open tickets with status
`pending_inspector_review`, oldest submission first, with the inspection photo
beside the owner's evidence. `review_ticket_evidence` only lets the inspector who
raised the ticket decide. **Mark resolved** sets the item to `resolved`; the ticket
becomes `resolved` once every item is. **Not resolved** requires feedback, can set
a new deadline (today or later) and returns the item to the owner (`open`,
`review_decision: "not_resolved"`). Owners cannot resubmit a resolved item.

No formal acceptance criteria were supplied with this story; these were derived from it.

| Acceptance criterion | Production behavior | Test case | Expected result |
| --- | --- | --- | --- |
| AC14.1 Inspector sees submitted evidence | The queue lists pending evidence from the inspector's own tickets with both photos, the owner's note, submission time and late status. | **MAN-14.1:** As Owner A, submit evidence (MAN-12.1). Sign in as the inspector who raised the ticket. | **Evidence to review** shows the item, store, finding, inspection photo, evidence photo and note. |
| AC14.2 Mark resolved | The item becomes **Resolved**; when it is the last open item the ticket becomes `resolved`. | **MAN-14.2:** Select **Mark resolved** (optionally with a comment). Sign in as Owner A. | The item leaves the queue. Owner A sees **Resolved** with the inspector's confirmation, the item leaves **Fix priorities** and no upload form is shown. With all items resolved the ticket shows `resolved`. |
| AC14.3 Not resolved | Feedback is required; the item returns to the owner with the feedback and optional new deadline. | **MAN-14.3:** Select **Not resolved** with no feedback, then with feedback and a new deadline. Sign in as Owner A. | Without feedback an error asks for it. With feedback, Owner A sees **Not resolved – resubmit**, the feedback and the new deadline; the item is back in **Fix priorities** and can be resubmitted. |
| AC14.4 Only the issuing inspector can decide | The function rejects any other user with `42501`; RLS hides other inspectors' tickets. | **MAN-14.4:** Sign in as a different inspector; then, as Owner A, call `review_ticket_evidence` from the browser console. | The other inspector's queue does not include the item. The console call is rejected with “You are not authorized to review evidence for this ticket.” |
| AC14.5 Resolved items stay resolved | `submit_ticket_evidence` rejects evidence for a resolved item; a resolved ticket accepts no new reviews or evidence. | **MAN-14.5:** As Owner A, call `submit_ticket_evidence` for a resolved item from the console. | Rejected with “The inspector has already marked this item as resolved.” |

## Baseline release checks

```bash
pnpm run lint
pnpm exec next build --webpack
```

Run both commands before release. They were used for every implementation delivery to date.
