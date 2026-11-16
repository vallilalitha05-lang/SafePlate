import { CalendarClock, Inbox } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LocalDateTime } from "@/components/ui/local-date-time";
import { VerifyInPersonButton } from "@/components/dashboard/verify-in-person-button";

export type ScheduledFollowUp = { id: string; ticket_id: string; item: string; reason: string; scheduled_for: string; store: string };

export function FollowUpInspections({ followUps }: { followUps: ScheduledFollowUp[] }) {
  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2"><CalendarClock className="h-5 w-5 text-primary" />Scheduled follow-up inspections{followUps.length > 0 && <span className="rounded-full bg-primary px-2 py-0.5 text-xs text-primary-foreground">{followUps.length}</span>}</CardTitle>
      <CardDescription>Fixes you rejected, to verify in person. Once you have confirmed the fix on site, approve it to resolve the issue and notify the store owner.</CardDescription>
    </CardHeader>
    <CardContent>
      {followUps.length === 0
        ? <div className="flex items-center gap-2 rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground"><Inbox className="h-4 w-4" />No follow-up inspections are scheduled.</div>
        : <ul className="space-y-3">{followUps.map((followUp) => <li key={followUp.id} className="rounded-lg border bg-background p-4">
            <div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-medium">{followUp.item}</p><p className="text-sm text-muted-foreground">{followUp.store}</p></div><p className="inline-flex items-center gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 px-2.5 py-1 text-sm text-amber-900"><CalendarClock className="h-4 w-4" /><LocalDateTime value={followUp.scheduled_for} /></p></div>
            <p className="mt-2 text-sm"><span className="font-medium">Reason for rejection:</span> “{followUp.reason}”</p>
            <VerifyInPersonButton ticketId={followUp.ticket_id} item={followUp.item} />
          </li>)}</ul>}
    </CardContent>
  </Card>;
}
