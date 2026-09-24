"use client";

import { useState } from "react";
import { CheckCircle2, CircleAlert, ClipboardCheck, LoaderCircle, MapPin } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

type Store = { id: string; name: string; address: string | null };

const checklistItems = [
  "Food is stored at safe temperatures",
  "Handwashing facilities are stocked and accessible",
  "Preparation surfaces are clean and sanitised",
  "Waste is contained and removed safely",
] as const;

type Result = "pass" | "needs_attention";

export function InspectionChecklist({ stores }: { stores: Store[] }) {
  const [selectedStoreId, setSelectedStoreId] = useState<string>();
  const [results, setResults] = useState<Record<string, Result>>({});
  const [notes, setNotes] = useState("");
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);
  const selectedStore = stores.find((store) => store.id === selectedStoreId);
  const complete = checklistItems.every((item) => results[item]);
  const overallStatus: Result | undefined = !complete ? undefined : checklistItems.some((item) => results[item] === "needs_attention") ? "needs_attention" : "pass";

  async function submitInspection() {
    if (!selectedStoreId) {
      setStatus("Select a store before starting the checklist.");
      return;
    }
    if (!complete || !overallStatus) {
      setStatus("Record a result for every checklist item before submitting.");
      return;
    }

    setStatus(undefined);
    setIsPending(true);
    const checklist = checklistItems.map((item) => ({ item, result: results[item] }));
    const { error } = await createClient().from("inspections").insert({
      store_id: selectedStoreId,
      checklist,
      overall_status: overallStatus,
      notes: notes.trim() || null,
    });
    setIsPending(false);

    if (error) {
      setStatus("We could not save this inspection. Please try again.");
      return;
    }

    setResults({});
    setNotes("");
    setStatus("Inspection saved. You can begin another checklist when ready.");
  }

  if (stores.length === 0) {
    return <Card><CardHeader><CardTitle className="flex items-center gap-2"><ClipboardCheck className="h-5 w-5 text-primary" />Start an inspection</CardTitle><CardDescription>There are no stores available to inspect yet. Store owners can link their stores from their workspace.</CardDescription></CardHeader></Card>;
  }

  return <div className="grid gap-6 lg:grid-cols-[0.8fr_1.2fr]">
    <Card className="h-fit">
      <CardHeader><CardTitle className="text-base">1. Select a store</CardTitle><CardDescription>Choose the food business you are visiting.</CardDescription></CardHeader>
      <CardContent className="space-y-3">
        {stores.map((store) => <Button key={store.id} type="button" variant="outline" onClick={() => { setSelectedStoreId(store.id); setStatus(undefined); }} className={`h-auto w-full justify-start rounded-lg p-4 text-left ${selectedStoreId === store.id ? "border-primary bg-accent" : "bg-background hover:bg-muted"}`}>
          <span className="block font-medium">{store.name}</span>
          {store.address && <span className="mt-1 flex items-center gap-1 text-sm text-muted-foreground"><MapPin className="h-3.5 w-3.5" />{store.address}</span>}
        </Button>)}
      </CardContent>
    </Card>

    <Card>
      <CardHeader><CardTitle className="text-base">2. Digital inspection checklist</CardTitle><CardDescription>{selectedStore ? `Recording inspection results for ${selectedStore.name}.` : "Select a store to begin recording results."}</CardDescription></CardHeader>
      <CardContent className="space-y-5">
        {checklistItems.map((item, index) => <div key={item} className="space-y-3 rounded-lg border p-4">
          <div className="flex items-start gap-3"><span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">{index + 1}</span><p className="pt-0.5 text-sm font-medium">{item}</p></div>
          <div className="flex flex-wrap gap-2 pl-9">
            <Button type="button" size="sm" variant={results[item] === "pass" ? "default" : "outline"} onClick={() => setResults((current) => ({ ...current, [item]: "pass" }))}><CheckCircle2 className="h-4 w-4" />Pass</Button>
            <Button type="button" size="sm" variant={results[item] === "needs_attention" ? "default" : "outline"} onClick={() => setResults((current) => ({ ...current, [item]: "needs_attention" }))}><CircleAlert className="h-4 w-4" />Needs attention</Button>
          </div>
        </div>)}
        <div className="space-y-2"><Label htmlFor="inspection-notes">Inspection notes <span className="text-muted-foreground">(optional)</span></Label><Input id="inspection-notes" value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={1000} placeholder="Add context for the store owner" /></div>
        {status && <p role="status" aria-live="polite" className={`rounded-md border px-3 py-2 text-sm ${status.startsWith("Inspection saved") ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status}</p>}
        <Button type="button" onClick={submitInspection} disabled={isPending || !selectedStoreId}>{isPending ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <ClipboardCheck className="h-4 w-4" />}Submit inspection{overallStatus === "needs_attention" ? " — needs attention" : ""}</Button>
      </CardContent>
    </Card>
  </div>;
}
