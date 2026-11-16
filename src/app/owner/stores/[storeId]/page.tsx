import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ShieldAlert } from "lucide-react";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { StoreHistoryView } from "@/components/dashboard/store-history";
import { getViewer } from "@/lib/auth";
import type { StoreHistory } from "@/lib/history";
import { createClient } from "@/lib/supabase/server";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const historyAuthorizationError = "You are not authorized to view this store's inspection history.";

export default async function OwnerStoreHistoryPage({ params }: { params: Promise<{ storeId: string }> }) {
  const { storeId } = await params;
  const viewer = await getViewer();
  if (viewer.role !== "store_owner") redirect("/inspector");

  const supabase = await createClient();
  // The function only returns stores this owner owns; any other store ID is
  // refused with an authorization error (AC21.2).
  const { data, error } = uuidPattern.test(storeId)
    ? await supabase.rpc("get_store_inspection_history", { p_store_id: storeId })
    : { data: null, error: { code: "42501", message: historyAuthorizationError } };

  const back = <Link href="/owner" className="inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline"><ArrowLeft className="h-4 w-4" />Back to workspace</Link>;

  if (error || !data) {
    return <main className="min-h-screen bg-muted/40"><section className="mx-auto max-w-4xl px-6 py-12">
      {back}
      <Card className="mt-6 border-destructive/30"><CardHeader>
        <CardTitle role="alert" className="flex items-center gap-2 text-destructive"><ShieldAlert className="h-5 w-5" />Not authorized</CardTitle>
        <CardDescription>{historyAuthorizationError} Store owners can only view the inspection history of stores linked to their own account.</CardDescription>
      </CardHeader></Card>
    </section></main>;
  }

  return <main className="min-h-screen bg-muted/40"><section className="mx-auto max-w-4xl px-6 py-12">
    {back}
    <div className="mt-6"><StoreHistoryView history={data as StoreHistory} viewer="store_owner" /></div>
  </section></main>;
}
