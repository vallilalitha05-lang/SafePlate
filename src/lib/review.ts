import type { FlaggedItem } from "@/lib/evidence";
import type { ValidationResult } from "@/lib/validation";

export const reviewMessages = {
  rejectionReason: "Provide a reason for rejecting this fix. The store owner will see it.",
  followUpInPast: "Choose a future date and time for the follow-up inspection.",
} as const;

// AC15.3 — Approve fix: a ticket is resolved only when every flagged item is
// resolved (mirrors review_ticket_evidence in the database).
export function allItemsResolved(items: Pick<FlaggedItem, "status">[]): boolean {
  return items.length > 0 && items.every((item) => item.status === "resolved");
}

// AC16.2 — Reject fix & schedule re-inspection: a reason is required.
export function validateRejectionReason(reason: string | null | undefined): ValidationResult {
  return reason && reason.trim() ? { valid: true } : { valid: false, message: reviewMessages.rejectionReason };
}

// AC16.3 — Reject fix & schedule re-inspection: the follow-up must be in the future.
export function validateFollowUpDate(when: string | Date | null | undefined, now = new Date()): ValidationResult {
  const date = when instanceof Date ? when : when ? new Date(when) : undefined;
  if (!date || Number.isNaN(date.getTime()) || date <= now) return { valid: false, message: reviewMessages.followUpInPast };
  return { valid: true };
}
