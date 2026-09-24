import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { createClient } from "@/lib/supabase/server";

export default async function OwnerPage() {
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");
  const supabase = await createClient();
  const { data: stores } = await supabase
    .from("stores")
    .select("id, name, address")
    .order("created_at", { ascending: true });

  return <Workspace role={viewer.role} name={viewer.full_name} stores={stores ?? []} />;
}
