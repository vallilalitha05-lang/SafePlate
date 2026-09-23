import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";

export default async function InspectorPage() {
  const viewer = await getViewer();
  if (viewer.role !== "inspector") redirect("/owner");
  return <Workspace role={viewer.role} name={viewer.full_name} />;
}
