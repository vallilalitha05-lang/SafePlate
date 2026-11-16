import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import type { FlaggedItem } from "@/lib/evidence";
import { storeNameOf, type StoreRelation } from "@/lib/stores";
import type { NotificationView, OwnerNotification } from "@/lib/notifications";
import { createClient } from "@/lib/supabase/server";


type TicketRow = {
  id: string;
  status: string;
  flagged_items: FlaggedItem[];
  created_at: string;
  stores: StoreRelation;
};

export default async function OwnerPage() {
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");

  const supabase = await createClient();
  const [{ data: stores }, { data: tickets }, { data: notifications }] = await Promise.all([
    supabase.from("stores").select("id, name, address").order("created_at", { ascending: true }),
    supabase.from("remediation_tickets").select("id, status, flagged_items, created_at, stores(name)").order("created_at", { ascending: false }),
    supabase.from("owner_notifications").select("id, ticket_id, kind, item, created_at, follow_up_inspections(reason, scheduled_for)").is("read_at", null).order("created_at", { ascending: false }),
  ]);
  const ownerTickets = (tickets ?? []) as unknown as TicketRow[];
  const photoPaths = ownerTickets.flatMap((ticket) =>
    ticket.flagged_items.flatMap((item) => (item.photo_path ? [item.photo_path] : [])),
  );
  const { data: signedPhotos } = photoPaths.length > 0
    ? await supabase.storage.from("inspection-photos").createSignedUrls(photoPaths, 60 * 60)
    : { data: [] };
  const photoUrls = Object.fromEntries(
    (signedPhotos ?? []).flatMap((photo) => photo.signedUrl ? [[photo.path, photo.signedUrl]] : []),
  );

  const ticketsById = new Map(ownerTickets.map((ticket) => [ticket.id, ticket]));
  const notificationViews: NotificationView[] = ((notifications ?? []) as OwnerNotification[]).map((notification) => {
    const ticket = ticketsById.get(notification.ticket_id);
    return { ...notification, store: storeNameOf(ticket?.stores, "your store"), ticketResolved: ticket?.status === "resolved" };
  });

  return <Workspace role={viewer.role} name={viewer.full_name} stores={stores ?? []} tickets={ownerTickets} notifications={notificationViews} photoUrls={photoUrls} />;
}
