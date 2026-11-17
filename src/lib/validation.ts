import { localToday } from "@/lib/deadlines";

/** Result of a client-side validation rule. */
export type ValidationResult = { valid: true } | { valid: false; message: string };

const ok: ValidationResult = { valid: true };
const fail = (message: string): ValidationResult => ({ valid: false, message });

export const MIN_PASSWORD_LENGTH = 8;
export const ACCEPTED_PHOTO_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

export const messages = {
  passwordRules: `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.`,
  passwordsDoNotMatch: "Passwords do not match.",
  emailInvalid: "Email is invalid. Enter an address like you@example.com.",
  commentRequired: "Add a written comment describing the issue.",
  photoType: "Attach a JPEG, PNG or WebP image.",
  photoSize: "Photos must be 5 MB or smaller.",
  deadlineRequired: "Set a remediation deadline.",
  deadlineInPast: "Choose a remediation deadline that is today or later.",
} as const;

// AC1.4 — Register with a role: password rules.
export function validatePassword(password: string): ValidationResult {
  return password.length >= MIN_PASSWORD_LENGTH ? ok : fail(messages.passwordRules);
}

// AC1.5 — Register with a role: the confirmation must match exactly.
export function validatePasswordMatch(password: string, confirmation: string): ValidationResult {
  return password === confirmation ? ok : fail(messages.passwordsDoNotMatch);
}

// AC1.6 / AC1.8 — Register with a role: a well-formed address (no spaces, one @,
// a dotted domain). Anything else — including SQL-injection strings — is
// rejected before any request is sent.
const emailPattern = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;
export function validateEmail(email: string): ValidationResult {
  return emailPattern.test(email.trim()) ? ok : fail(messages.emailInvalid);
}

export type ChecklistResult = "pass" | "fail";
export type ChecklistResponse = { result?: ChecklistResult; comment?: string; deadline?: string };

// AC5.3 — Mark checklist items: names of the items that have no pass/fail yet, in order.
export function findUnmarkedItems(items: readonly string[], responses: Record<string, ChecklistResponse | undefined>): string[] {
  return items.filter((item) => !responses[item]?.result);
}

// AC6.3 — Attach a written comment: whitespace-only comments are rejected.
export function validateComment(comment: string | null | undefined): ValidationResult {
  return comment && comment.trim() ? ok : fail(messages.commentRequired);
}

// AC7.2 / AC7.3 — Attach a photo: JPEG, PNG or WebP up to 5 MB.
export function validatePhoto(file: { type: string; size: number }): ValidationResult {
  if (!(ACCEPTED_PHOTO_TYPES as readonly string[]).includes(file.type)) return fail(messages.photoType);
  if (file.size > MAX_PHOTO_BYTES) return fail(messages.photoSize);
  return ok;
}

// AC8.1 / AC8.2 — Set a remediation deadline: today or later (YYYY-MM-DD, local date).
export function validateDeadline(deadline: string | null | undefined, today = localToday()): ValidationResult {
  if (!deadline) return fail(messages.deadlineRequired);
  return deadline >= today ? ok : fail(messages.deadlineInPast);
}

// AC9.3 — Submit a completed inspection: every item marked; every failed item
// has a comment and a deadline of today or later. Returns the first problem.
export function validateInspectionSubmit({ storeId, items, responses, today = localToday() }: {
  storeId?: string;
  items: readonly string[];
  responses: Record<string, ChecklistResponse | undefined>;
  today?: string;
}): ValidationResult {
  if (!storeId) return fail("Select a store before starting the checklist.");
  const unmarked = findUnmarkedItems(items, responses);
  if (unmarked.length) return fail(`Mark every checklist item before submitting: ${unmarked.join("; ")}.`);
  const failed = items.filter((item) => responses[item]?.result === "fail");
  const missingComments = failed.filter((item) => !validateComment(responses[item]?.comment).valid);
  if (missingComments.length) return fail(`Add a written comment for every failed item before submitting: ${missingComments.join("; ")}.`);
  const missingDeadlines = failed.filter((item) => !responses[item]?.deadline);
  if (missingDeadlines.length) return fail(`Set a remediation deadline for every failed item before submitting: ${missingDeadlines.join("; ")}.`);
  const pastDeadlines = failed.filter((item) => !validateDeadline(responses[item]?.deadline, today).valid);
  if (pastDeadlines.length) return fail(`Choose a remediation deadline that is today or later: ${pastDeadlines.join("; ")}.`);
  return ok;
}
