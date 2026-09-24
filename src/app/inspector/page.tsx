import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";
import { InspectionChecklist } from "@/components/dashboard/inspection-checklist";
import { createClient } from "@/lib/supabase/server";

export default async function InspectorPage() {
  const viewer = await getViewer();
  if (viewer.role !== "inspector") redirect("/owner");
  const supabase = await createClient();
  const { data: stores } = await supabase
    .from("stores")
    .select("id, name, address")
    .order("name", { ascending: true });

  return <Workspace role={viewer.role} name={viewer.full_name}><section className="mt-8"><InspectionChecklist stores={stores ?? []} /></section></Workspace>;
}
