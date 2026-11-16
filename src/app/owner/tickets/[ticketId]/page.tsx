import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ImageIcon, ShieldAlert, TicketCheck } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { EvidenceUploadForm } from "@/components/dashboard/evidence-upload-form";
import { OverdueNotice } from "@/components/dashboard/overdue-notice";
import { getViewer } from "@/lib/auth";
import { authorizationError, wasSentBack, type FlaggedItem } from "@/lib/evidence";
import { ItemStatusBadges, ReviewOutcome } from "@/components/dashboard/item-status";
import { settledLabel, sortByDeadline } from "@/lib/deadlines";
import { DeadlineBadge } from "@/components/dashboard/deadline-badge";
import { createClient } from "@/lib/supabase/server";

type TicketRow = {
  id: string;
  status: string;
  owner_id: string;
  flagged_items: FlaggedItem[];
  created_at: string;
  stores: { name: string }[] | { name: string } | null;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function storeName(stores: TicketRow["stores"]) {
  if (!stores) return "Your store";
  return Array.isArray(stores) ? stores[0]?.name ?? "Your store" : stores.name;
}

export default async function OwnerTicketPage({ params }: { params: Promise<{ ticketId: string }> }) {
  const { ticketId } = await params;
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;

  // RLS only returns tickets owned by the signed-in owner; the owner_id check is
  // a second guard. Anything else is treated as an unauthorized attempt (AC12.3).
  const { data } = uuidPattern.test(ticketId)
    ? await supabase.from("remediation_tickets").select("id, status, owner_id, flagged_items, created_at, stores(name)").eq("id", ticketId).maybeSingle()
    : { data: null };
  const ticket = data as TicketRow | null;

  const back = <Link href="/owner" className="inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline"><ArrowLeft className="h-4 w-4" />Back to workspace</Link>;

  if (!ticket || ticket.owner_id !== userId) {
    return <main className="min-h-screen bg-muted/40"><section className="mx-auto max-w-3xl px-6 py-12">
      {back}
      <Card className="mt-6 border-destructive/30"><CardHeader><CardTitle role="alert" className="flex items-center gap-2 text-destructive"><ShieldAlert className="h-5 w-5" />Not authorized</CardTitle><CardDescription>{authorizationError} Evidence can only be submitted by the owner of the store the ticket was issued to.</CardDescription></CardHeader></Card>
    </section></main>;
  }

  const paths = ticket.flagged_items.flatMap((item) => [
    ...(item.photo_path ? [{ bucket: "inspection-photos", path: item.photo_path }] : []),
    ...(item.evidence_photo_path ? [{ bucket: "remediation-evidence", path: item.evidence_photo_path }] : []),
  ]);
  const signed = await Promise.all(["inspection-photos", "remediation-evidence"].map(async (bucket) => {
    const bucketPaths = paths.filter((entry) => entry.bucket === bucket).map((entry) => entry.path);
    if (bucketPaths.length === 0) return [];
    const { data: urls } = await supabase.storage.from(bucket).createSignedUrls(bucketPaths, 60 * 60);
    return (urls ?? []).flatMap((url) => url.signedUrl && url.path ? [[`${bucket}/${url.path}`, url.signedUrl] as const] : []);
  }));
  const photoUrls: Record<string, string> = Object.fromEntries(signed.flat());
  const isOpen = ticket.status === "open";

  return <main className="min-h-screen bg-muted/40"><section className="mx-auto max-w-3xl px-6 py-12">
    {back}
    <Card className="mt-6">
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-2"><CardTitle className="flex items-center gap-2"><TicketCheck className="h-5 w-5 text-primary" />{storeName(ticket.stores)}</CardTitle><Badge>{ticket.status}</Badge></div>
        <CardDescription>Issued {new Date(ticket.created_at).toLocaleDateString()}. Issues are listed by remediation deadline, soonest first. Upload a photo showing each flagged issue has been fixed and submit it for inspector review.</CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="space-y-4">{sortByDeadline(ticket.flagged_items).map((item, index) => {
          const pendingReview = item.status === "pending_inspector_review";
          const resolved = item.status === "resolved";
          const reInspection = item.status === "re_inspection_required";
          const inspectionPhoto = item.photo_path ? photoUrls[`inspection-photos/${item.photo_path}`] : undefined;
          const evidencePhoto = item.evidence_photo_path ? photoUrls[`remediation-evidence/${item.evidence_photo_path}`] : undefined;
          return <li key={item.item} className="rounded-lg border bg-background p-4">
            <div className="flex flex-wrap items-start justify-between gap-2"><p className="font-medium">{item.item}</p><ItemStatusBadges item={item} /></div>
            {item.comment && <p className="mt-1 text-sm text-muted-foreground">{item.comment}</p>}
            <DeadlineBadge className="mt-2" deadline={item.remediation_deadline} settled={settledLabel(item)} />
            {inspectionPhoto && <a className="mt-2 inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline" href={inspectionPhoto} target="_blank" rel="noreferrer"><ImageIcon className="h-4 w-4" />View inspection photo</a>}
            {isOpen && !pendingReview && !resolved && !reInspection && <OverdueNotice deadline={item.remediation_deadline} />}
            <ReviewOutcome item={item} />
            {item.evidence_photo_path && <div className="mt-3 rounded-md bg-muted/60 p-3 text-sm">
              <p><span className="font-medium">{wasSentBack(item) || reInspection ? "Previous evidence" : "Evidence submitted"}</span>{item.evidence_submitted_at ? ` ${new Date(item.evidence_submitted_at).toLocaleString()}` : ""}</p>
              {item.evidence_note && <p className="mt-1 text-muted-foreground">{item.evidence_note}</p>}
              {evidencePhoto && <a className="mt-2 inline-flex items-center gap-2 font-medium text-primary underline-offset-4 hover:underline" href={evidencePhoto} target="_blank" rel="noreferrer"><ImageIcon className="h-4 w-4" />View submitted evidence</a>}
            </div>}
            {isOpen && !resolved && !reInspection && <EvidenceUploadForm ticketId={ticket.id} item={item.item} index={index} hasEvidence={pendingReview} />}
          </li>;
        })}</ul>
      </CardContent>
    </Card>
  </section></main>;
}
