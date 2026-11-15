export const authorizationError = "You are not authorized to submit evidence for this ticket.";

export type FlaggedItemStatus = "open" | "pending_inspector_review";

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
};

