import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { InspectionChecklist } from "@/components/dashboard/inspection-checklist";
import { EvidenceReviewQueue, type ReviewQueueEntry } from "@/components/dashboard/evidence-review-queue";
import type { FlaggedItem } from "@/lib/evidence";
import { createClient } from "@/lib/supabase/server";

type InspectorTicket = {
  id: string;
  status: string;
  flagged_items: FlaggedItem[];
  stores: { name: string }[] | { name: string } | null;
};

function storeName(stores: InspectorTicket["stores"]) {
  if (!stores) return "Store";
  return Array.isArray(stores) ? stores[0]?.name ?? "Store" : stores.name;
}

export default async function InspectorPage() {
  const viewer = await getViewer();
  if (viewer.role !== "inspector") redirect("/owner");
  const supabase = await createClient();
  // RLS limits tickets to those raised from this inspector's own inspections.
  const [{ data: stores }, { data: tickets }] = await Promise.all([
    supabase.from("stores").select("id, name, address").order("name", { ascending: true }),
    supabase.from("remediation_tickets").select("id, status, flagged_items, stores(name)").eq("status", "open"),
  ]);

  const queue: ReviewQueueEntry[] = ((tickets ?? []) as InspectorTicket[])
    .flatMap((ticket) => ticket.flagged_items
      .filter((item) => item.status === "pending_inspector_review")
      .map((item) => ({ ticketId: ticket.id, store: storeName(ticket.stores), item })))
    .sort((a, b) => (a.item.evidence_submitted_at ?? "").localeCompare(b.item.evidence_submitted_at ?? ""));

  const signed = await Promise.all((["inspection-photos", "remediation-evidence"] as const).map(async (bucket) => {
    const paths = queue.flatMap(({ item }) => {
      const path = bucket === "inspection-photos" ? item.photo_path : item.evidence_photo_path;
      return path ? [path] : [];
    });
    if (paths.length === 0) return [];
    const { data: urls } = await supabase.storage.from(bucket).createSignedUrls(paths, 60 * 60);
    return (urls ?? []).flatMap((url) => url.signedUrl && url.path ? [[`${bucket}/${url.path}`, url.signedUrl] as const] : []);
  }));
  const photoUrls: Record<string, string> = Object.fromEntries(signed.flat());

  return <Workspace role={viewer.role} name={viewer.full_name}>
    <section className="mt-8"><EvidenceReviewQueue entries={queue} photoUrls={photoUrls} /></section>
    <section className="mt-8"><InspectionChecklist stores={stores ?? []} /></section>
  </Workspace>;
}
