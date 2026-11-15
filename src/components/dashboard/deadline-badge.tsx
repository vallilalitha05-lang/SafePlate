"use client";

import { useSyncExternalStore } from "react";
import { AlertTriangle, CalendarClock, CheckCircle2, Clock } from "lucide-react";
import { cn } from "@/lib/utils";
import { daysUntil, deadlineUrgency, describeCountdown, formatDeadline, localToday, type DeadlineUrgency } from "@/lib/deadlines";

const styles: Record<DeadlineUrgency, string> = {
  overdue: "border-destructive/30 bg-destructive/10 text-destructive",
  today: "border-destructive/30 bg-destructive/10 text-destructive",
  soon: "border-amber-500/40 bg-amber-500/10 text-amber-800",
  upcoming: "border-primary/20 bg-primary/5 text-primary",
  none: "border-border bg-muted text-muted-foreground",
};

// Recompute "today" from the viewer's own clock. The server renders without a
// countdown (null snapshot) so there is no hydration mismatch across timezones.
function subscribe(onChange: () => void) {
  const timer = window.setInterval(onChange, 60_000);
  return () => window.clearInterval(timer);
}

export function useToday() {
  return useSyncExternalStore(subscribe, () => localToday(), () => null);
}

export function DeadlineBadge({ deadline, submitted = false, className }: { deadline: string | null; submitted?: boolean; className?: string }) {
  const today = useToday();
  const days = today ? daysUntil(deadline, today) : null;
  const urgency = submitted ? "none" : deadlineUrgency(days);
  const Icon = submitted ? CheckCircle2 : urgency === "overdue" || urgency === "today" ? AlertTriangle : urgency === "soon" ? Clock : CalendarClock;

  return <p className={cn("inline-flex flex-wrap items-center gap-x-2 gap-y-1 rounded-md border px-2.5 py-1 text-sm", styles[urgency], className)} data-urgency={urgency}>
    <Icon className="h-4 w-4 shrink-0" />
    <span><span className="font-medium">Fix by:</span> <time dateTime={deadline ?? undefined}>{formatDeadline(deadline)}</time></span>
    {submitted
      ? <span className="font-medium">· Evidence submitted</span>
      : today && deadline && <span className="font-semibold">· {describeCountdown(days)}</span>}
  </p>;
}
