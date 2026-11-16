import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { InspectionChecklist } from "@/components/dashboard/inspection-checklist";
import { EvidenceReviewQueue, type ReviewQueueEntry } from "@/components/dashboard/evidence-review-queue";
import { FollowUpInspections, type ScheduledFollowUp } from "@/components/dashboard/follow-up-inspections";
import { InspectorNotifications } from "@/components/dashboard/inspector-notifications";
import { OverdueIssues, type OverdueEntry } from "@/components/dashboard/overdue-issues";
import type { FlaggedItem } from "@/lib/evidence";
import { toInspectorNotification, type InspectorNotificationRow } from "@/lib/inspector-notifications";
import { compareByDeadline } from "@/lib/deadlines";
import { StoreOperatingStatus } from "@/components/dashboard/store-operating-status";
import { toActiveSuspension, type SuspensionRow } from "@/lib/suspensions";
import { storeNameOf, type StoreRelation } from "@/lib/stores";
import { createClient } from "@/lib/supabase/server";

type InspectorTicket = {
  id: string;
  store_id: string;
  status: string;
  flagged_items: FlaggedItem[];
  stores: StoreRelation;
};

export default async function InspectorPage() {
  const viewer = await getViewer();
  if (viewer.role !== "inspector") redirect("/owner");
  const supabase = await createClient();
  // RLS limits tickets to those raised from this inspector's own inspections.
  const { data: claims } = await supabase.auth.getClaims();
  const viewerId = claims?.claims?.sub;
  const [{ data: stores }, { data: tickets }, { data: followUpRows }, { data: notificationRows }, { data: suspensionRows }] = await Promise.all([
    supabase.from("stores").select("id, name, address, operating_status").order("name", { ascending: true }),
    supabase.from("remediation_tickets").select("id, store_id, status, flagged_items, stores(name)").eq("status", "open"),
    supabase.from("follow_up_inspections").select("id, ticket_id, item, reason, scheduled_for, stores(name)").eq("status", "scheduled").order("scheduled_for", { ascending: true }),
    supabase.from("inspector_notifications").select("id, ticket_id, kind, item, created_at, remediation_tickets(stores(name))").is("read_at", null).order("created_at", { ascending: false }),
    supabase.from("store_suspensions").select("id, store_id, reason, item, suspended_at, suspended_by, stores(name)").is("lifted_at", null).order("suspended_at", { ascending: false }),
  ]);
  const suspensions = ((suspensionRows ?? []) as unknown as SuspensionRow[]).map((row) => toActiveSuspension(row, viewerId));
  const suspendedStoreIds = new Set((stores ?? []).filter((store) => store.operating_status === "suspended").map((store) => store.id));
  const activeStores = (stores ?? []).filter((store) => store.operating_status !== "suspended");
  const notifications = ((notificationRows ?? []) as unknown as InspectorNotificationRow[]).map(toInspectorNotification);
  const followUps: ScheduledFollowUp[] = ((followUpRows ?? []) as (Omit<ScheduledFollowUp, "store"> & { stores: StoreRelation })[])
    .map(({ stores: store, ...followUp }) => ({ ...followUp, store: storeNameOf(store, "Store") }));

  const queue: ReviewQueueEntry[] = ((tickets ?? []) as InspectorTicket[])
    .flatMap((ticket) => ticket.flagged_items
      .filter((item) => item.status === "pending_inspector_review")
      .map((item) => ({ ticketId: ticket.id, store: storeNameOf(ticket.stores, "Store"), item })))
    .sort((a, b) => (a.item.evidence_submitted_at ?? "").localeCompare(b.item.evidence_submitted_at ?? ""));

  const overdue: OverdueEntry[] = ((tickets ?? []) as InspectorTicket[])
    .flatMap((ticket) => ticket.flagged_items
      .filter((item) => item.status === "overdue")
      .map((item) => ({ ticketId: ticket.id, storeId: ticket.store_id, storeSuspended: suspendedStoreIds.has(ticket.store_id), store: storeNameOf(ticket.stores, "Store"), item })))
    .sort((a, b) => compareByDeadline(a.item, b.item));

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
    {notifications.length > 0 && <section className="mt-8"><InspectorNotifications notifications={notifications} /></section>}
    <section className="mt-8"><OverdueIssues entries={overdue} /></section>
    <section className="mt-8"><StoreOperatingStatus activeStores={activeStores} suspensions={suspensions} /></section>
    <section className="mt-8"><EvidenceReviewQueue entries={queue} photoUrls={photoUrls} /></section>
    <section className="mt-8"><FollowUpInspections followUps={followUps} /></section>
    <section className="mt-8"><InspectionChecklist stores={stores ?? []} /></section>
  </Workspace>;
}
