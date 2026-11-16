import { AlertTriangle, Ban, CheckCircle2 } from "lucide-react";
import { SuspendStoreForm } from "@/components/dashboard/suspend-store-form";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { DeadlineBadge } from "@/components/dashboard/deadline-badge";
import { formatDeadline } from "@/lib/deadlines";
import type { FlaggedItem } from "@/lib/evidence";

export type OverdueEntry = { ticketId: string; storeId: string; storeSuspended: boolean; store: string; item: FlaggedItem };

/** Issues flagged overdue by the daily deadline check on the inspector's own tickets. */
export function OverdueIssues({ entries }: { entries: OverdueEntry[] }) {
  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2"><AlertTriangle className="h-5 w-5 text-destructive" />Overdue issues{entries.length > 0 && <span className="rounded-full bg-destructive px-2 py-0.5 text-xs text-white">{entries.length}</span>}</CardTitle>
      <CardDescription>Issues on your tickets that passed their remediation deadline with no evidence submitted. These are grounds to initiate suspension procedures.</CardDescription>
    </CardHeader>
    <CardContent>
      {entries.length === 0
        ? <div className="flex items-center gap-2 rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground"><CheckCircle2 className="h-4 w-4" />No issues are overdue.</div>
        : <ul className="space-y-3">{entries.map(({ ticketId, storeId, storeSuspended, store, item }, index) => <li key={`${ticketId}-${item.item}`} className="rounded-lg border border-destructive/30 bg-background p-4" data-ticket={ticketId}>
            <div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-medium">{item.item}</p><p className="text-sm text-muted-foreground">{store}</p></div><span className="rounded-full bg-destructive px-2.5 py-0.5 text-xs font-semibold text-white">Overdue</span></div>
            {item.comment && <p className="mt-2 text-sm"><span className="font-medium">Your finding:</span> {item.comment}</p>}
            <DeadlineBadge className="mt-2" deadline={item.remediation_deadline} />
            {item.overdue_since && <p className="mt-2 text-xs text-muted-foreground">Flagged overdue by the daily deadline check on {formatDeadline(item.overdue_since)}.</p>}
            {storeSuspended
              ? <p className="mt-3 inline-flex items-center gap-2 rounded-md border border-destructive/30 bg-destructive/10 px-3 py-1.5 text-sm font-medium text-destructive"><Ban className="h-4 w-4" />{store} is suspended</p>
              : <details className="mt-3 rounded-md border bg-muted/30 p-3"><summary className="cursor-pointer text-sm font-medium text-destructive">Initiate suspension of {store}</summary><div className="mt-3"><SuspendStoreForm storeId={storeId} storeName={store} ticketId={ticketId} item={item.item} idPrefix={`suspend-overdue-${index}`} defaultReason={`Overdue issue: ${item.item}. The remediation deadline (${formatDeadline(item.remediation_deadline)}) passed with no evidence submitted.`} /></div></details>}
          </li>)}</ul>}
    </CardContent>
  </Card>;
}
