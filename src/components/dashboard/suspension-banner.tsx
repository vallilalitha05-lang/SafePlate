import { Ban } from "lucide-react";
import { LocalDateTime } from "@/components/ui/local-date-time";
import type { ActiveSuspension } from "@/lib/suspensions";

/** Shown to a store owner for each of their stores that is currently suspended. */
export function SuspensionBanner({ suspensions }: { suspensions: ActiveSuspension[] }) {
  if (suspensions.length === 0) return null;
  return <div className="space-y-3">{suspensions.map((suspension) => <div key={suspension.id} role="alert" className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 p-4 text-destructive">
    <Ban className="mt-0.5 h-5 w-5 shrink-0" />
    <div className="text-sm">
      <p className="text-base font-semibold">{suspension.store} is suspended</p>
      <p className="mt-1">An inspector suspended this store&apos;s operating status on <LocalDateTime value={suspension.suspended_at} />.</p>
      <p className="mt-1"><span className="font-medium">Reason:</span> {suspension.reason}</p>
      {suspension.item && <p className="mt-1"><span className="font-medium">Related issue:</span> {suspension.item}</p>}
      <p className="mt-1">Fix the outstanding issues. An inspector will lift the suspension once compliance is confirmed.</p>
    </div>
  </div>)}</div>;
}
