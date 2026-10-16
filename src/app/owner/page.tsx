import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { createClient } from "@/lib/supabase/server";

export default async function OwnerPage() {
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");
  const supabase = await createClient();
  const [{ data: stores }, { data: tickets }] = await Promise.all([
    supabase.from("stores").select("id, name, address").order("created_at", { ascending: true }),
    supabase.from("remediation_tickets").select("id, status, flagged_items, created_at, stores(name)").order("created_at", { ascending: false }),
  ]);

  return <Workspace role={viewer.role} name={viewer.full_name} stores={stores ?? []} tickets={tickets ?? []} />;
}
