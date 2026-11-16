import { Ban, CheckCircle2, ClipboardList, History, MapPin, Repeat, ShieldCheck, TrendingUp, XCircle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LocalDateTime } from "@/components/ui/local-date-time";
import { ItemStatusBadges } from "@/components/dashboard/item-status";
import { formatDeadline } from "@/lib/deadlines";
import { summarizeHistory, type StoreHistory } from "@/lib/history";

function Stat({ label, value, hint }: { label: string; value: React.ReactNode; hint?: React.ReactNode }) {
  return <div className="rounded-lg border bg-background p-4"><p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p><p className="mt-1 text-2xl font-semibold">{value}</p>{hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}</div>;
}

/** Full inspection history for one store: trends, every inspection and the suspension record. */
export function StoreHistoryView({ history, viewer }: { history: StoreHistory; viewer: "inspector" | "store_owner" }) {
  const { store, inspections, suspensions } = history;
  const summary = summarizeHistory(inspections);
  const repeat = summary.violations.filter((violation) => violation.count > 1);

  return <div className="space-y-6">
    <div>
      <p className="flex items-center gap-2 text-sm font-medium text-primary"><History className="h-4 w-4" />{viewer === "store_owner" ? "Your compliance history" : "Inspection history"}</p>
      <h1 className="mt-1 flex flex-wrap items-center gap-3 text-3xl font-semibold tracking-tight">{store.name}{store.operating_status === "suspended" ? <Badge variant="destructive">Suspended</Badge> : <Badge variant="success">Active</Badge>}</h1>
      {store.address && <p className="mt-1 flex items-center gap-1 text-muted-foreground"><MapPin className="h-4 w-4" />{store.address}</p>}
    </div>

    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <Stat label="Inspections" value={summary.total} hint={summary.total ? `${summary.passed} passed · ${summary.failed} failed` : "None yet"} />
      <Stat label="Pass rate" value={summary.passRate === null ? "–" : `${summary.passRate}%`} hint={summary.results.length > 0 && <span className="flex gap-1" aria-label="Results oldest to newest">{summary.results.map((result, index) => <span key={index} title={result} className={`inline-block h-2.5 w-2.5 rounded-full ${result === "pass" ? "bg-emerald-600" : "bg-destructive"}`} />)}</span>} />
      <Stat label="Last inspected" value={summary.lastInspectedAt ? <span className="text-base"><LocalDateTime value={summary.lastInspectedAt} dateOnly /></span> : "–"} />
      <Stat label="Repeat violations" value={repeat.length} hint={repeat.length ? "Items failed more than once" : "No item failed twice"} />
    </div>

    <Card>
      <CardHeader><CardTitle className="flex items-center gap-2"><TrendingUp className="h-5 w-5 text-primary" />Violation trends</CardTitle><CardDescription>{viewer === "store_owner" ? "Checklist items your store has failed, most frequent first. Repeat violations are the ones to watch." : "Checklist items this store has failed, most frequent first."}</CardDescription></CardHeader>
      <CardContent>
        {summary.violations.length === 0
          ? <p className="flex items-center gap-2 text-sm text-muted-foreground"><ShieldCheck className="h-4 w-4" />No violations recorded.</p>
          : <ul className="space-y-2">{summary.violations.map((violation) => <li key={violation.item} className="flex flex-wrap items-center justify-between gap-2 rounded-md border bg-background px-3 py-2 text-sm">
              <span className="flex items-center gap-2 font-medium">{violation.count > 1 && <Repeat className="h-4 w-4 text-destructive" aria-label="Repeat violation" />}{violation.item}</span>
              <span className="text-muted-foreground">Failed {violation.count} time{violation.count === 1 ? "" : "s"} · last <LocalDateTime value={violation.lastFailedAt} dateOnly /></span>
            </li>)}</ul>}
      </CardContent>
    </Card>

    <Card>
      <CardHeader><CardTitle className="flex items-center gap-2"><ClipboardList className="h-5 w-5 text-primary" />All inspections</CardTitle><CardDescription>{summary.total === 0 ? "This store has not been inspected yet." : `Every inspection of ${store.name}, newest first.`}</CardDescription></CardHeader>
      <CardContent>
        {inspections.length > 0 && <ol className="space-y-4">{inspections.map((inspection) => {
          const failures = inspection.checklist.filter((entry) => entry.result === "fail");
          const passes = inspection.checklist.length - failures.length;
          const ticketItems = new Map((inspection.ticket?.items ?? []).map((item) => [item.item, item]));
          return <li key={inspection.id} className="rounded-lg border bg-background p-4" data-inspection={inspection.id}>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="font-medium"><LocalDateTime value={inspection.created_at} /></p>
                <p className="text-sm text-muted-foreground">{viewer === "inspector" && inspection.conducted_by_viewer ? "Inspected by you" : `Inspected by ${inspection.inspector_name}`}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                {inspection.overall_status === "pass" ? <Badge variant="success">Passed</Badge> : <Badge variant="destructive">Failed</Badge>}
                {inspection.ticket && <Badge variant="outline">Ticket {inspection.ticket.status}</Badge>}
              </div>
            </div>
            <p className="mt-2 flex items-center gap-2 text-sm text-muted-foreground"><CheckCircle2 className="h-4 w-4 text-emerald-600" />{passes} of {inspection.checklist.length} checklist items passed</p>
            {failures.length > 0 && <ul className="mt-3 space-y-2">{failures.map((entry) => {
              const ticketItem = ticketItems.get(entry.item);
              return <li key={entry.item} className="rounded-md border border-destructive/20 bg-destructive/5 p-3 text-sm">
                <div className="flex flex-wrap items-start justify-between gap-2"><p className="flex items-center gap-2 font-medium"><XCircle className="h-4 w-4 text-destructive" />{entry.item}</p>{ticketItem && <ItemStatusBadges item={ticketItem} />}</div>
                {entry.comment && <p className="mt-1 text-muted-foreground">{entry.comment}</p>}
                {entry.remediation_deadline && <p className="mt-1 text-xs text-muted-foreground">Remediation deadline: {formatDeadline(ticketItem?.remediation_deadline ?? entry.remediation_deadline)}</p>}
              </li>;
            })}</ul>}
            {inspection.notes && <p className="mt-3 text-sm"><span className="font-medium">Notes:</span> {inspection.notes}</p>}
          </li>;
        })}</ol>}
      </CardContent>
    </Card>

    <Card>
      <CardHeader><CardTitle className="flex items-center gap-2"><Ban className="h-5 w-5 text-destructive" />Suspension record</CardTitle><CardDescription>Every time this store&apos;s operating status was suspended.</CardDescription></CardHeader>
      <CardContent>
        {suspensions.length === 0
          ? <p className="flex items-center gap-2 text-sm text-muted-foreground"><ShieldCheck className="h-4 w-4" />This store has never been suspended.</p>
          : <ul className="space-y-3">{suspensions.map((suspension) => <li key={suspension.id} className="rounded-md border bg-background p-3 text-sm">
              <div className="flex flex-wrap items-center justify-between gap-2"><p className="font-medium">Suspended <LocalDateTime value={suspension.suspended_at} /></p>{suspension.lifted_at ? <Badge variant="outline">Lifted</Badge> : <Badge variant="destructive">Active</Badge>}</div>
              <p className="mt-1"><span className="font-medium">Reason:</span> {suspension.reason}</p>
              {suspension.lifted_at && <p className="mt-1 text-muted-foreground">Lifted <LocalDateTime value={suspension.lifted_at} />{suspension.lift_reason ? ` · ${suspension.lift_reason}` : ""}</p>}
            </li>)}</ul>}
      </CardContent>
    </Card>
  </div>;
}
