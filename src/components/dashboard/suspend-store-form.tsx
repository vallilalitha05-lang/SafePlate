"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Ban, LoaderCircle, ShieldAlert, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

const textareaClass = "flex min-h-20 w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50";

type Store = { id: string; name: string };
type Props = {
  /** Choose from these stores, or pass `storeId` to suspend a specific store. */
  stores?: Store[];
  storeId?: string;
  storeName?: string;
  ticketId?: string;
  item?: string;
  defaultReason?: string;
  idPrefix: string;
};

export function SuspendStoreForm({ stores, storeId, storeName, ticketId, item, defaultReason = "", idPrefix }: Props) {
  const router = useRouter();
  const reasonRef = useRef<HTMLTextAreaElement>(null);
  const [selected, setSelected] = useState(storeId ?? "");
  const [reason, setReason] = useState(defaultReason);
  const [reasonMissing, setReasonMissing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<{ ok: boolean; message: string }>();

  async function suspend() {
    if (!selected) { setStatus({ ok: false, message: "Choose the store to suspend." }); return; }
    if (!reason.trim()) {
      setReasonMissing(true);
      setStatus({ ok: false, message: "Provide a reason for suspending this store. It is recorded and shown to the store owner." });
      reasonRef.current?.focus();
      return;
    }
    setBusy(true);
    setStatus(undefined);
    const { error } = await createClient().rpc("suspend_store", { p_store_id: selected, p_reason: reason.trim(), p_ticket_id: ticketId ?? null, p_item: item ?? null });
    setBusy(false);
    if (error) { setStatus({ ok: false, message: error.code === "42501" ? "Only inspectors can suspend a store." : error.message }); return; }
    const name = storeName ?? stores?.find((store) => store.id === selected)?.name ?? "The store";
    setStatus({ ok: true, message: `${name} is now suspended. The suspension is recorded and the store owner has been notified.` });
    setReason("");
    router.refresh();
  }

  return <div className="space-y-3">
    {!storeId && <div className="space-y-2">
      <Label htmlFor={`${idPrefix}-store`}>Store</Label>
      <select id={`${idPrefix}-store`} value={selected} onChange={(event) => setSelected(event.target.value)} disabled={busy} className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm">
        <option value="">Select an active store…</option>
        {stores?.map((store) => <option key={store.id} value={store.id}>{store.name}</option>)}
      </select>
    </div>}
    <div className="space-y-2">
      <Label htmlFor={`${idPrefix}-reason`}>Reason for suspension <span className="text-muted-foreground">(required; recorded and shown to the store owner)</span></Label>
      <textarea ref={reasonRef} id={`${idPrefix}-reason`} value={reason} onChange={(event) => { setReason(event.target.value); if (event.target.value.trim()) setReasonMissing(false); }} maxLength={1000} disabled={busy} aria-invalid={reasonMissing} className={`${textareaClass} ${reasonMissing ? "border-destructive" : ""}`} placeholder="e.g. Handwashing station has been overdue for 3 days with no evidence submitted" />
    </div>
    {status && <p role={status.ok ? "status" : "alert"} className={`flex items-start gap-2 rounded-md border px-3 py-2 text-sm ${status.ok ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status.ok ? <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0" /> : <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />}{status.message}</p>}
    <Button type="button" size="sm" variant="destructive" onClick={suspend} disabled={busy}>{busy ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <Ban className="h-4 w-4" />}Suspend store</Button>
  </div>;
}

export function LiftSuspensionForm({ storeId, storeName, idPrefix }: { storeId: string; storeName: string; idPrefix: string }) {
  const router = useRouter();
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function lift() {
    if (!reason.trim()) { setError("Provide a reason for lifting this suspension."); return; }
    setBusy(true);
    setError(undefined);
    const { error: rpcError } = await createClient().rpc("lift_store_suspension", { p_store_id: storeId, p_reason: reason.trim() });
    setBusy(false);
    if (rpcError) setError(rpcError.message);
    else router.refresh();
  }

  return <div className="mt-3 flex flex-wrap items-end gap-2 border-t pt-3">
    <div className="min-w-56 flex-1 space-y-1">
      <Label htmlFor={`${idPrefix}-lift`} className="text-xs">Reason for reinstating {storeName} <span className="text-muted-foreground">(required)</span></Label>
      <input id={`${idPrefix}-lift`} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={1000} disabled={busy} placeholder="e.g. Re-inspected on site: all issues fixed" className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm" />
    </div>
    <Button type="button" size="sm" variant="outline" onClick={lift} disabled={busy}>{busy ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}Lift suspension</Button>
    {error && <p role="alert" className="w-full text-sm text-destructive">{error}</p>}
  </div>;
}
