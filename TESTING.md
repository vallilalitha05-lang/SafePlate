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

## Baseline release checks

```bash
pnpm run lint
pnpm exec next build --webpack
```

Run both commands before release. They were used for every implementation delivery to date.
