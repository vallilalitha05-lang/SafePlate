import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Workspace } from "@/components/dashboard/workspace";

export default async function OwnerPage() {
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");
  return <Workspace role={viewer.role} name={viewer.full_name} />;
}
