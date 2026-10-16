import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { createClient } from "@/lib/supabase/server";

type TicketItem = {
  item: string;
  comment: string | null;
  remediation_deadline: string | null;
  photo_path: string | null;
};

type TicketRow = {
  id: string;
  status: string;
  flagged_items: TicketItem[];
  created_at: string;
  stores: { name: string }[] | null;
};

type TicketNotification = {
  id: string;
  ticket_id: string;
  created_at: string;
};

export default async function OwnerPage() {
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");

  const supabase = await createClient();
  const [{ data: stores }, { data: tickets }, { data: notifications }] = await Promise.all([
    supabase.from("stores").select("id, name, address").order("created_at", { ascending: true }),
    supabase.from("remediation_tickets").select("id, status, flagged_items, created_at, stores(name)").order("created_at", { ascending: false }),
    supabase.from("owner_notifications").select("id, ticket_id, created_at").order("created_at", { ascending: false }),
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

  return <Workspace role={viewer.role} name={viewer.full_name} stores={stores ?? []} tickets={ownerTickets} notifications={(notifications ?? []) as TicketNotification[]} photoUrls={photoUrls} />;
}
