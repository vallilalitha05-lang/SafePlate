export const authorizationError = "You are not authorized to submit evidence for this ticket.";

export const reviewAuthorizationError = "You are not authorized to review evidence for this ticket.";

export type FlaggedItemStatus = "open" | "overdue" | "pending_inspector_review" | "re_inspection_required" | "resolved";
export type ReviewDecision = "resolved" | "not_resolved" | "re_inspection";

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
  follow_up_inspection_id?: string | null;
  follow_up_scheduled_for?: string | null;
  verified_in_person?: boolean;
  /** Set by the daily deadline check when the deadline passed with no evidence. */
  overdue_since?: string | null;
};

/** The inspector reviewed the last evidence and found the issue not yet fixed. */
export function wasSentBack(item: FlaggedItem) {
  return item.status !== "pending_inspector_review" && item.status !== "resolved" && item.review_decision === "not_resolved";
}

