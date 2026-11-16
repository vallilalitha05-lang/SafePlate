"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, LoaderCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { reviewAuthorizationError } from "@/lib/evidence";
import { createClient } from "@/lib/supabase/client";

/** Approves an item after the follow-up physical inspection confirmed the fix. */
export function VerifyInPersonButton({ ticketId, item }: { ticketId: string; item: string }) {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function approve() {
    setBusy(true);
    setError(undefined);
    const { error: rpcError } = await createClient().rpc("review_ticket_evidence", { p_ticket_id: ticketId, p_item: item, p_decision: "resolved", p_comment: note.trim() || null });
    setBusy(false);
    if (rpcError) setError(rpcError.code === "42501" ? reviewAuthorizationError : rpcError.message || "We could not save your decision. Please try again.");
    else router.refresh();
  }

  return <div className="mt-3 flex flex-wrap items-end gap-2 border-t pt-3">
    <div className="min-w-56 flex-1 space-y-1">
      <Label htmlFor={`verify-note-${ticketId}-${item}`} className="text-xs">On-site note <span className="text-muted-foreground">(optional)</span></Label>
      <Input id={`verify-note-${ticketId}-${item}`} value={note} onChange={(event) => setNote(event.target.value)} maxLength={500} placeholder="e.g. Verified on site: fridge at 4°C" disabled={busy} />
    </div>
    <Button type="button" size="sm" onClick={approve} disabled={busy}>{busy ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}Verified in person – approve fix</Button>
    {error && <p role="alert" className="w-full text-sm text-destructive">{error}</p>}
  </div>;
}
