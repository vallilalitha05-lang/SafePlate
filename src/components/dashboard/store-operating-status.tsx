import { Ban, ShieldCheck } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LocalDateTime } from "@/components/ui/local-date-time";
import { LiftSuspensionForm, SuspendStoreForm } from "@/components/dashboard/suspend-store-form";
import type { ActiveSuspension } from "@/lib/suspensions";

/** Inspector view of store operating status: suspend a store and see/lift active suspensions. */
export function StoreOperatingStatus({ activeStores, suspensions }: { activeStores: { id: string; name: string }[]; suspensions: ActiveSuspension[] }) {
  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2"><Ban className="h-5 w-5 text-destructive" />Store operating status{suspensions.length > 0 && <span className="rounded-full bg-destructive px-2 py-0.5 text-xs text-white">{suspensions.length} suspended</span>}</CardTitle>
      <CardDescription>Suspending a store records the suspension officially, marks the store as suspended for every inspector and notifies the store owner.</CardDescription>
    </CardHeader>
    <CardContent className="space-y-6">
      <section>
        <h3 className="mb-3 text-sm font-semibold">Currently suspended</h3>
        {suspensions.length === 0
          ? <p className="flex items-center gap-2 rounded-lg border border-dashed bg-muted/40 p-4 text-sm text-muted-foreground"><ShieldCheck className="h-4 w-4" />No stores are suspended.</p>
          : <ul className="space-y-3">{suspensions.map((suspension) => <li key={suspension.id} className="rounded-lg border border-destructive/30 bg-background p-4">
              <div className="flex flex-wrap items-start justify-between gap-2"><p className="font-medium">{suspension.store}</p><span className="rounded-full bg-destructive px-2.5 py-0.5 text-xs font-semibold text-white">Suspended</span></div>
              <p className="mt-1 text-sm text-muted-foreground">Since <LocalDateTime value={suspension.suspended_at} /> · by {suspension.suspendedByViewer ? "you" : "another inspector"}{suspension.item ? ` · overdue issue: ${suspension.item}` : ""}</p>
              <p className="mt-2 text-sm"><span className="font-medium">Reason:</span> {suspension.reason}</p>
              <LiftSuspensionForm storeId={suspension.store_id} storeName={suspension.store} idPrefix={`lift-${suspension.id}`} />
            </li>)}</ul>}
      </section>
      <section className="border-t pt-5">
        <h3 className="mb-3 text-sm font-semibold">Suspend a store</h3>
        {activeStores.length === 0
          ? <p className="text-sm text-muted-foreground">There are no active stores to suspend.</p>
          : <SuspendStoreForm stores={activeStores} idPrefix="suspend-any" />}
      </section>
    </CardContent>
  </Card>;
}
