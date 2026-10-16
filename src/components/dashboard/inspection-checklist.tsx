"use client";

import { useState } from "react";
import { CheckCircle2, CircleAlert, ClipboardCheck, ImagePlus, LoaderCircle, MapPin } from "lucide-react";
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

type Result = "pass" | "fail";
type ChecklistResponse = { result?: Result; comment: string; photo?: File };
const acceptedImageTypes = ["image/jpeg", "image/png", "image/webp"];
const maximumPhotoSize = 5 * 1024 * 1024;

export function InspectionChecklist({ stores }: { stores: Store[] }) {
  const [selectedStoreId, setSelectedStoreId] = useState<string>();
  const [responses, setResponses] = useState<Record<string, ChecklistResponse>>({});
  const [notes, setNotes] = useState("");
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);
  const selectedStore = stores.find((store) => store.id === selectedStoreId);
  const unmarkedItems = checklistItems.filter((item) => !responses[item]?.result);
  const failedItemsMissingComments = checklistItems.filter((item) => responses[item]?.result === "fail" && !responses[item]?.comment.trim());
  const complete = unmarkedItems.length === 0;
  const overallStatus: Result | undefined = !complete ? undefined : checklistItems.some((item) => responses[item]?.result === "fail") ? "fail" : "pass";

  function setResult(item: string, result: Result) {
    setResponses((current) => ({
      ...current,
      [item]: result === "pass" ? { result, comment: "" } : { ...current[item], result, comment: current[item]?.comment ?? "" },
    }));
    setStatus(undefined);
  }

  function setComment(item: string, comment: string) {
    setResponses((current) => ({ ...current, [item]: { ...current[item], comment } }));
  }

  function setPhoto(item: string, file: File | undefined) {
    if (file && !acceptedImageTypes.includes(file.type)) {
      setStatus("Attach a JPEG, PNG, or WebP image for a failed item.");
      return;
    }
    if (file && file.size > maximumPhotoSize) {
      setStatus("Each inspection photo must be 5 MB or smaller.");
      return;
    }
    setResponses((current) => ({ ...current, [item]: { ...current[item], comment: current[item]?.comment ?? "", photo: file } }));
    setStatus(undefined);
  }

  async function submitInspection() {
    if (!selectedStoreId) {
      setStatus("Select a store before starting the checklist.");
      return;
    }
    if (!complete || !overallStatus) {
      setStatus(`Mark every checklist item before submitting: ${unmarkedItems.join("; ")}.`);
      return;
    }
    if (failedItemsMissingComments.length > 0) {
      setStatus(`Add a written comment for every failed item before submitting: ${failedItemsMissingComments.join("; ")}.`);
      return;
    }

    setStatus(undefined);
    setIsPending(true);
    const supabase = createClient();

    try {
      const { data: { user }, error: userError } = await supabase.auth.getUser();
      if (userError || !user) {
        setStatus("Your session has expired. Please sign in again before submitting.");
        return;
      }

      const checklist = await Promise.all(checklistItems.map(async (item) => {
        const response = responses[item];
        let photoPath: string | null = null;

        if (response.photo) {
          const extension = response.photo.type === "image/png" ? "png" : response.photo.type === "image/webp" ? "webp" : "jpg";
          const path = `${user.id}/${crypto.randomUUID()}.${extension}`;
          const { error: uploadError } = await supabase.storage.from("inspection-photos").upload(path, response.photo, { cacheControl: "3600", contentType: response.photo.type, upsert: false });
          if (uploadError) throw uploadError;
          photoPath = path;
        }

        return { item, result: response.result, comment: response.comment.trim() || null, photo_path: photoPath };
      }));

      const { error } = await supabase.from("inspections").insert({
        store_id: selectedStoreId,
        checklist,
        overall_status: overallStatus,
        notes: notes.trim() || null,
      });
      if (error) throw error;

      setResponses({});
      setNotes("");
      setStatus("Inspection saved. You can begin another checklist when ready.");
    } catch {
      setStatus("We could not save this inspection. Please try again.");
    } finally {
      setIsPending(false);
    }
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
        {checklistItems.map((item, index) => <div key={item} className={`space-y-3 rounded-lg border p-4 ${responses[item]?.result === "fail" ? "border-destructive/50 bg-destructive/5" : ""}`}>
          <div className="flex items-start gap-3"><span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">{index + 1}</span><p className="pt-0.5 text-sm font-medium">{item}</p></div>
          <div className="flex flex-wrap gap-2 pl-9">
            <Button type="button" size="sm" variant={responses[item]?.result === "pass" ? "default" : "outline"} onClick={() => setResult(item, "pass")}><CheckCircle2 className="h-4 w-4" />Pass</Button>
            <Button type="button" size="sm" variant={responses[item]?.result === "fail" ? "destructive" : "outline"} onClick={() => setResult(item, "fail")}><CircleAlert className="h-4 w-4" />Fail</Button>
          </div>
          {responses[item]?.result === "fail" && <div className="space-y-3 border-t border-destructive/20 pt-3 pl-9">
            <p className="text-sm text-destructive">A written comment is required for every failed item. Add a photo if useful.</p>
            <div className="space-y-2"><Label htmlFor={`comment-${index}`}>Comment <span className="text-destructive">(required)</span></Label><Input id={`comment-${index}`} value={responses[item]?.comment ?? ""} onChange={(event) => setComment(item, event.target.value)} maxLength={500} required aria-required="true" placeholder="Describe what needs attention" /></div>
            <div className="space-y-2"><Label htmlFor={`photo-${index}`} className="flex items-center gap-2"><ImagePlus className="h-4 w-4" />Photo <span className="text-muted-foreground">(optional, JPEG, PNG, or WebP; max 5 MB)</span></Label><Input id={`photo-${index}`} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setPhoto(item, event.target.files?.[0])} />{responses[item]?.photo && <p className="text-sm text-muted-foreground">Attached: {responses[item].photo?.name}</p>}</div>
          </div>}
        </div>)}
        <div className="space-y-2"><Label htmlFor="inspection-notes">Inspection notes <span className="text-muted-foreground">(optional)</span></Label><Input id="inspection-notes" value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={1000} placeholder="Add context for the store owner" /></div>
        {status && <p role="status" aria-live="polite" className={`rounded-md border px-3 py-2 text-sm ${status.startsWith("Inspection saved") ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status}</p>}
        <Button type="button" onClick={submitInspection} disabled={isPending || !selectedStoreId}>{isPending ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <ClipboardCheck className="h-4 w-4" />}{isPending ? "Saving inspection…" : "Submit inspection"}{overallStatus === "fail" ? " — failed items recorded" : ""}</Button>
      </CardContent>
    </Card>
  </div>;
}
