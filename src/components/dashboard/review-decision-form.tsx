"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, CheckCircle2, LoaderCircle, MessageSquareWarning, ShieldAlert, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { localToday } from "@/lib/deadlines";
import { reviewAuthorizationError, type ReviewDecision } from "@/lib/evidence";
import { createClient } from "@/lib/supabase/client";

type Status = { kind: "success" | "error" | "unauthorized"; message: string };
type Panel = "reject" | "request" | undefined;

const rejectionReasonPrompt = "Provide a reason for rejecting this fix. The store owner will see it.";

/** Current local time as a value for <input type="datetime-local"> (YYYY-MM-DDTHH:mm). */
function localDateTimeValue(date = new Date()) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function ReviewDecisionForm({ ticketId, item, index }: { ticketId: string; item: string; index: number }) {
  const router = useRouter();
  const reasonRef = useRef<HTMLInputElement>(null);
  const [reason, setReason] = useState("");
  const [reasonMissing, setReasonMissing] = useState(false);
  const [panel, setPanel] = useState<Panel>();
  const [followUpAt, setFollowUpAt] = useState("");
  const [newDeadline, setNewDeadline] = useState("");
  const [status, setStatus] = useState<Status>();
  const [pending, setPending] = useState<ReviewDecision>();

  function promptForReason(message: string) {
    setReasonMissing(true);
    setStatus({ kind: "error", message });
    reasonRef.current?.focus();
  }

  async function decide(decision: ReviewDecision) {
    const trimmed = reason.trim();
    // AC16.2: a rejection without a reason is refused and the inspector is prompted.
    if (decision === "re_inspection" && !trimmed) return promptForReason(rejectionReasonPrompt);
    if (decision === "not_resolved" && !trimmed) return promptForReason("Explain what the store owner still needs to show before requesting new evidence.");

    let followUpIso: string | null = null;
    if (decision === "re_inspection") {
      const when = followUpAt ? new Date(followUpAt) : undefined;
      if (!when || Number.isNaN(when.getTime()) || when <= new Date()) {
        setStatus({ kind: "error", message: "Choose a future date and time for the follow-up inspection." });
        return;
      }
      followUpIso = when.toISOString();
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
        p_follow_up_at: followUpIso,
      });
      if (error) {
        if (error.code === "42501") setStatus({ kind: "unauthorized", message: reviewAuthorizationError });
        else if (decision === "re_inspection" && /reason/i.test(error.message)) promptForReason(rejectionReasonPrompt);
        else setStatus({ kind: "error", message: error.message || "We could not save your decision. Please try again." });
        return;
      }
      const ticketResolved = (data as { ticket_status?: string } | null)?.ticket_status === "resolved";
      setStatus({
        kind: "success",
        message: decision === "resolved"
          ? `Approved. The issue is resolved and the store owner has been notified.${ticketResolved ? " Every issue on this ticket is now resolved, so the ticket is closed." : ""}`
          : decision === "re_inspection"
            ? `Fix rejected. A follow-up inspection is scheduled for ${new Date(followUpIso!).toLocaleString()} and the store owner has been notified with your reason.`
            : "New evidence requested. The store owner will see your feedback.",
      });
      router.refresh();
    } catch {
      setStatus({ kind: "error", message: "We could not save your decision. Please try again." });
    } finally {
      setPending(undefined);
    }
  }

  const busy = pending !== undefined;
  const reasonId = `review-reason-${index}`;
  return <div className="mt-4 space-y-3 border-t pt-4">
    <div className="space-y-2">
      <Label htmlFor={reasonId}>Reason / feedback for the store owner <span className="text-muted-foreground">(required to reject or request new evidence)</span></Label>
      <Input
        ref={reasonRef}
        id={reasonId}
        value={reason}
        onChange={(event) => { setReason(event.target.value); if (event.target.value.trim()) setReasonMissing(false); }}
        maxLength={500}
        placeholder="e.g. Thermometer reading is not visible in the photo"
        aria-invalid={reasonMissing}
        aria-describedby={reasonMissing ? `${reasonId}-error` : undefined}
        className={reasonMissing ? "border-destructive focus-visible:ring-destructive" : undefined}
        disabled={busy}
      />
      {reasonMissing && <p id={`${reasonId}-error`} className="text-sm text-destructive">A reason is required.</p>}
    </div>

    {panel === "reject" && <div className="space-y-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-3">
      <Label htmlFor={`follow-up-at-${index}`} className="flex items-center gap-2"><CalendarClock className="h-4 w-4" />Follow-up physical inspection</Label>
      <Input id={`follow-up-at-${index}`} type="datetime-local" min={localDateTimeValue()} value={followUpAt} onChange={(event) => setFollowUpAt(event.target.value)} disabled={busy} className="max-w-xs" />
      <p className="text-xs text-muted-foreground">The item will be marked “re-inspection required” and the store owner notified with your reason and this visit time.</p>
      <div className="flex flex-wrap gap-2">
        <Button type="button" size="sm" variant="destructive" onClick={() => decide("re_inspection")} disabled={busy}>{pending === "re_inspection" ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <XCircle className="h-4 w-4" />}Reject and schedule re-inspection</Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setPanel(undefined)} disabled={busy}>Cancel</Button>
      </div>
    </div>}

    {panel === "request" && <div className="space-y-2 rounded-md border bg-muted/40 p-3">
      <Label htmlFor={`review-deadline-${index}`}>New deadline <span className="text-muted-foreground">(optional; keeps the current deadline if left blank)</span></Label>
      <Input id={`review-deadline-${index}`} type="date" min={localToday()} value={newDeadline} onChange={(event) => setNewDeadline(event.target.value)} disabled={busy} className="max-w-xs" />
      <div className="flex flex-wrap gap-2">
        <Button type="button" size="sm" variant="outline" onClick={() => decide("not_resolved")} disabled={busy}>{pending === "not_resolved" ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <MessageSquareWarning className="h-4 w-4" />}Send back for new evidence</Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setPanel(undefined)} disabled={busy}>Cancel</Button>
      </div>
    </div>}

    {status && <p role={status.kind === "success" ? "status" : "alert"} aria-live="polite" className={`flex items-start gap-2 rounded-md border px-3 py-2 text-sm ${status.kind === "success" ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status.kind === "unauthorized" && <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />}{status.message}</p>}

    {panel === undefined && <div className="flex flex-wrap gap-2">
      <Button type="button" size="sm" onClick={() => decide("resolved")} disabled={busy}>{pending === "resolved" ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}Approve fix</Button>
      <Button type="button" size="sm" variant="destructive" onClick={() => { setStatus(undefined); setPanel("reject"); }} disabled={busy}><XCircle className="h-4 w-4" />Reject fix…</Button>
      <Button type="button" size="sm" variant="outline" onClick={() => { setStatus(undefined); setPanel("request"); }} disabled={busy}><MessageSquareWarning className="h-4 w-4" />Request new evidence…</Button>
    </div>}
  </div>;
}
