"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ImagePlus, LoaderCircle, Send, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { authorizationError } from "@/lib/evidence";
import { createClient } from "@/lib/supabase/client";
import { validatePhoto } from "@/lib/validation";


type Status = { kind: "success" | "error" | "unauthorized"; message: string };

function isAuthorizationFailure(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const { code, statusCode, status, message } = error as { code?: string; statusCode?: string | number; status?: number; message?: string };
  return code === "42501"
    || String(statusCode) === "403"
    || status === 403
    || /row-level security|not authorized|unauthorized/i.test(message ?? "");
}

export function EvidenceUploadForm({ ticketId, item, index, hasEvidence }: { ticketId: string; item: string; index: number; hasEvidence: boolean }) {
  const router = useRouter();
  const [photo, setPhoto] = useState<File>();
  const [note, setNote] = useState("");
  const [status, setStatus] = useState<Status>();
  const [isPending, setIsPending] = useState(false);

  function choosePhoto(file: File | undefined) {
    const photoCheck = file ? validatePhoto(file) : undefined;
    if (photoCheck && !photoCheck.valid) {
      setPhoto(undefined);
      setStatus({ kind: "error", message: photoCheck.message });
      return;
    }
    setPhoto(file);
    setStatus(undefined);
  }

  async function submitEvidence() {
    if (!photo) {
      setStatus({ kind: "error", message: "Choose a photo showing the fix before submitting." });
      return;
    }

    setIsPending(true);
    setStatus(undefined);
    const supabase = createClient();

    try {
      const { data: { user }, error: userError } = await supabase.auth.getUser();
      if (userError || !user) {
        setStatus({ kind: "error", message: "Your session has expired. Please sign in again before submitting." });
        return;
      }

      const extension = photo.type === "image/png" ? "png" : photo.type === "image/webp" ? "webp" : "jpg";
      const path = `${user.id}/${ticketId}/${crypto.randomUUID()}.${extension}`;
      const { error: uploadError } = await supabase.storage.from("remediation-evidence").upload(path, photo, { cacheControl: "3600", contentType: photo.type, upsert: false });
      if (uploadError) {
        setStatus(isAuthorizationFailure(uploadError) ? { kind: "unauthorized", message: authorizationError } : { kind: "error", message: "We could not upload that photo. Please try again." });
        return;
      }

      const { data, error } = await supabase.rpc("submit_ticket_evidence", { p_ticket_id: ticketId, p_item: item, p_photo_path: path, p_note: note.trim() || null });
      if (error) {
        setStatus(isAuthorizationFailure(error) ? { kind: "unauthorized", message: authorizationError } : { kind: "error", message: error.message || "We could not submit this evidence. Please try again." });
        return;
      }

      const resolvedLate = Boolean((data as { resolved_late?: boolean } | null)?.resolved_late);
      setPhoto(undefined);
      setNote("");
      setStatus({
        kind: "success",
        message: resolvedLate
          ? "Evidence submitted for inspector review. The deadline had passed, so this item is marked resolved late."
          : "Evidence submitted. This item is now pending inspector review.",
      });
      router.refresh();
    } catch {
      setStatus({ kind: "error", message: "We could not submit this evidence. Please try again." });
    } finally {
      setIsPending(false);
    }
  }

  return <div className="mt-4 space-y-3 border-t pt-4">
    <div className="space-y-2">
      <Label htmlFor={`evidence-photo-${index}`} className="flex items-center gap-2"><ImagePlus className="h-4 w-4" />{hasEvidence ? "Replace evidence photo" : "Evidence photo"} <span className="text-muted-foreground">(JPEG, PNG, or WebP; max 5 MB)</span></Label>
      <Input id={`evidence-photo-${index}`} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePhoto(event.target.files?.[0])} disabled={isPending} />
      {photo && <p className="text-sm text-muted-foreground">Selected: {photo.name}</p>}
    </div>
    <div className="space-y-2">
      <Label htmlFor={`evidence-note-${index}`}>Note for the inspector <span className="text-muted-foreground">(optional)</span></Label>
      <Input id={`evidence-note-${index}`} value={note} onChange={(event) => setNote(event.target.value)} maxLength={500} placeholder="Describe what was fixed" disabled={isPending} />
    </div>
    {status && <p role={status.kind === "success" ? "status" : "alert"} aria-live="polite" className={`flex items-start gap-2 rounded-md border px-3 py-2 text-sm ${status.kind === "success" ? "border-primary/20 bg-primary/10 text-primary" : "border-destructive/20 bg-destructive/10 text-destructive"}`}>{status.kind === "unauthorized" && <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />}{status.message}</p>}
    <Button type="button" size="sm" onClick={submitEvidence} disabled={isPending}>{isPending ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}{isPending ? "Submitting…" : hasEvidence ? "Resubmit for inspector review" : "Submit for inspector review"}</Button>
  </div>;
}
