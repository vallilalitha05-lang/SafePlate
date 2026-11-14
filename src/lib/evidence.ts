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

export function isPastDeadline(deadline: string | null, today = new Date()) {
  if (!deadline) return false;
  const local = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  return deadline < local;
}
