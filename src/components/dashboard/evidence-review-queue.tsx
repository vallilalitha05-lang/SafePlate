import { ClipboardCheck, ImageIcon, Inbox } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { DeadlineBadge } from "@/components/dashboard/deadline-badge";
import { ItemStatusBadges } from "@/components/dashboard/item-status";
import { ReviewDecisionForm } from "@/components/dashboard/review-decision-form";
import type { FlaggedItem } from "@/lib/evidence";

export type ReviewQueueEntry = { ticketId: string; store: string; item: FlaggedItem };

function Photo({ label, url }: { label: string; url?: string }) {
  return <figure className="space-y-1">
    <figcaption className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</figcaption>
    {url
      ? <a href={url} target="_blank" rel="noreferrer" className="block overflow-hidden rounded-md border bg-muted">
          {/* Signed Supabase URLs expire, so next/image optimisation is not used here. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={url} alt={label} className="h-48 w-full object-cover" />
        </a>
      : <div className="flex h-48 items-center justify-center rounded-md border border-dashed bg-muted/40 text-sm text-muted-foreground"><ImageIcon className="mr-2 h-4 w-4" />No photo</div>}
  </figure>;
}

export function EvidenceReviewQueue({ entries, photoUrls }: { entries: ReviewQueueEntry[]; photoUrls: Record<string, string> }) {
  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2"><ClipboardCheck className="h-5 w-5 text-primary" />Evidence to review{entries.length > 0 && <span className="rounded-full bg-primary px-2 py-0.5 text-xs text-primary-foreground">{entries.length}</span>}</CardTitle>
      <CardDescription>Store owners have submitted evidence for these flagged issues on your inspections. Compare it with what you found and decide whether each issue is resolved. Oldest submissions first.</CardDescription>
    </CardHeader>
    <CardContent>
      {entries.length === 0
        ? <div className="flex items-center gap-2 rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground"><Inbox className="h-4 w-4" />No evidence is waiting for your review.</div>
        : <ul className="space-y-4">{entries.map(({ ticketId, store, item }, index) => <li key={`${ticketId}-${item.item}`} className="rounded-lg border bg-background p-4">
            <div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-medium">{item.item}</p><p className="text-sm text-muted-foreground">{store}</p></div><ItemStatusBadges item={item} /></div>
            {item.comment && <p className="mt-2 text-sm"><span className="font-medium">Your finding:</span> {item.comment}</p>}
            <DeadlineBadge className="mt-2" deadline={item.remediation_deadline} settled={item.resolved_late ? "Submitted after the deadline" : "Submitted on time"} />
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <Photo label="At inspection" url={item.photo_path ? photoUrls[`inspection-photos/${item.photo_path}`] : undefined} />
              <Photo label="Owner's evidence" url={item.evidence_photo_path ? photoUrls[`remediation-evidence/${item.evidence_photo_path}`] : undefined} />
            </div>
            <div className="mt-3 rounded-md bg-muted/60 p-3 text-sm">
              <p><span className="font-medium">Submitted</span>{item.evidence_submitted_at ? ` ${new Date(item.evidence_submitted_at).toLocaleString()}` : ""}</p>
              <p className="mt-1 text-muted-foreground">{item.evidence_note ? `Owner's note: ${item.evidence_note}` : "No note from the owner."}</p>
              {item.review_decision === "not_resolved" && item.review_comment && <p className="mt-1 text-muted-foreground">Your earlier feedback: “{item.review_comment}”</p>}
            </div>
            <ReviewDecisionForm ticketId={ticketId} item={item.item} index={index} />
          </li>)}</ul>}
    </CardContent>
  </Card>;
}
