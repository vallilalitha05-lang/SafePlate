export const authorizationError = "You are not authorized to submit evidence for this ticket.";

export const reviewAuthorizationError = "You are not authorized to review evidence for this ticket.";

export type FlaggedItemStatus = "open" | "pending_inspector_review" | "resolved";
export type ReviewDecision = "resolved" | "not_resolved";

export type FlaggedItem = {
  item: string;
  comment: string | null;
  remediation_deadline: string | null;
  photo_path: string | null;
  status?: FlaggedItemStatus;
  evidence_photo_path?: string | null;
  evidence_note?: string | null;
  evidence_submitted_at?: string | null;
  resolved_late?: boolean;
  review_decision?: ReviewDecision | null;
  review_comment?: string | null;
  reviewed_at?: string | null;
};

/** The inspector reviewed the last evidence and found the issue not yet fixed. */
export function wasSentBack(item: FlaggedItem) {
  return item.status !== "pending_inspector_review" && item.status !== "resolved" && item.review_decision === "not_resolved";
}

