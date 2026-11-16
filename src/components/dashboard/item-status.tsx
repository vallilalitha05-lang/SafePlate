import { CheckCircle2, MessageSquareWarning } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { wasSentBack, type FlaggedItem } from "@/lib/evidence";

/** Status badges for a flagged item, shared by the owner and inspector views. */
export function ItemStatusBadges({ item }: { item: FlaggedItem }) {
  return <div className="flex flex-wrap gap-2">
    {item.status === "resolved" ? <Badge variant="success">Resolved</Badge>
      : item.status === "pending_inspector_review" ? <Badge>Pending inspector review</Badge>
      : wasSentBack(item) ? <Badge variant="destructive">Not resolved – resubmit</Badge>
      : <Badge variant="outline">Awaiting evidence</Badge>}
    {item.resolved_late && <Badge variant="destructive">Resolved late</Badge>}
  </div>;
}

/** The inspector's decision on the latest evidence, as shown to the store owner. */
export function ReviewOutcome({ item }: { item: FlaggedItem }) {
  const reviewed = item.reviewed_at ? ` on ${new Date(item.reviewed_at).toLocaleDateString()}` : "";
  if (item.status === "resolved") {
    return <div className="mt-3 flex items-start gap-2 rounded-md border border-emerald-600/30 bg-emerald-600/10 px-3 py-2 text-sm text-emerald-800">
      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
      <div><p className="font-medium">The inspector confirmed this issue is resolved{reviewed}.</p>{item.review_comment && <p className="mt-1">{item.review_comment}</p>}</div>
    </div>;
  }
  if (wasSentBack(item)) {
    return <div role="alert" className="mt-3 flex items-start gap-2 rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
      <MessageSquareWarning className="mt-0.5 h-4 w-4 shrink-0" />
      <div><p className="font-medium">The inspector found this issue is not resolved yet{reviewed}.</p>{item.review_comment && <p className="mt-1">“{item.review_comment}”</p>}<p className="mt-1">Fix it and upload new evidence by the deadline above.</p></div>
    </div>;
  }
  return null;
}
