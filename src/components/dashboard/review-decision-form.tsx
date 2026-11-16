"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, LoaderCircle, ShieldAlert, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { localToday } from "@/lib/deadlines";
import { reviewAuthorizationError, type ReviewDecision } from "@/lib/evidence";
import { createClient } from "@/lib/supabase/client";

type Status = { kind: "success" | "error" | "unauthorized"; message: string };

export function ReviewDecisionForm({ ticketId, item, index }: { ticketId: string; item: string; index: number }) {
  const router = useRouter();
  const [comment, setComment] = useState("");
  const [newDeadline, setNewDeadline] = useState("");
  const [status, setStatus] = useState<Status>();
  const [pending, setPending] = useState<ReviewDecision>();

  async function decide(decision: ReviewDecision) {
    const trimmed = comment.trim();
    if (decision === "not_resolved" && !trimmed) {
      setStatus({ kind: "error", message: "Explain what still needs to be fixed before marking this as not resolved." });
      return;
    }
    if (decision === "not_resolved" && newDeadline && newDeadline < localToday()) {
      setStatus({ kind: "error", message: "A new deadline must be today or later." });
      return;
    }

    setPending(decision);
    setStatus(undefined);
    try {
      const { data, error } = await createClient().rpc("review_ticket_evidence", {
        p_ticket_id: ticketId,
        p_item: item,
        p_decision: decision,
        p_comment: trimmed || null,
        p_new_deadline: decision === "not_resolved" && newDeadline ? newDeadline : null,
      });
      if (error) {
        setStatus(error.code === "42501"
          ? { kind: "unauthorized", message: reviewAuthorizationError }
          : { kind: "error", message: error.message || "We could not save your decision. Please try again." });
        return;
      }
      const ticketResolved = (data as { ticket_status?: string } | null)?.ticket_status === "resolved";
      setStatus({
        kind: "success",
        message: decision === "resolved"
          ? ticketResolved ? "Approved. The issue is resolved and the store owner has been notified. Every issue on this ticket is now resolved, so the ticket is closed." : "Approved. The issue is resolved and the store owner has been notified."
          : "Sent back to the store owner with your feedback.",
      });
      router.refresh();
    } catch {
      setStatus({ kind: "error", message: "We could not save your decision. Please try again." });
    } finally {
      setPending(undefined);
    }
  }

  const busy = pending !== undefined;
  return <div className="mt-4 space-y-3 border-t pt-4">
    <div className="space-y-2">
      <Label htmlFor={`review-comment-${index}`}>Feedback for the store owner <span className="text-muted-foreground">(required if not resolved)</span></Label>
      <Input id={`review-comment-${index}`} value={comment} onChange={(event) => setComment(event.target.value)} maxLength={500} placeholder="e.g. Soap dispenser is still empty" disabled={busy} />
    </div>
    <div className="space-y-2">
      <Label htmlFor={`review-deadline-${index}`}>New deadline if not resolved <span className="text-muted-foreground">(optional; keeps the current deadline if left blank)</span></Label>
      <Input id={`review-deadline-${index}`} type="date" min={localToday()} value={newDeadline} onChange={(event) => setNewDeadline(event.target.value)} disabled={busy} className="max-w-xs" />
    </div>
    {status && <p role={status.kind === "success" ? "status" : "alert"} aria-live="polite" className={`flex items-start gap-2 rounded-md border px-3 py-2 text-sm ${status.kind === "success" ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status.kind === "unauthorized" && <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />}{status.message}</p>}
    <div className="flex flex-wrap gap-2">
      <Button type="button" size="sm" onClick={() => decide("resolved")} disabled={busy}>{pending === "resolved" ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}Approve fix</Button>
      <Button type="button" size="sm" variant="outline" onClick={() => decide("not_resolved")} disabled={busy}>{pending === "not_resolved" ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <XCircle className="h-4 w-4" />}Not resolved</Button>
    </div>
  </div>;
}
