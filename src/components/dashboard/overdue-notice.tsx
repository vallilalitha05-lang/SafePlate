"use client";

import { AlertTriangle } from "lucide-react";
import { daysUntil } from "@/lib/deadlines";
import { useToday } from "@/components/dashboard/deadline-badge";

/** Shown on an open item whose deadline has passed in the viewer's own timezone. */
export function OverdueNotice({ deadline }: { deadline: string | null }) {
  const today = useToday();
  const days = today ? daysUntil(deadline, today) : null;
  if (days === null || days >= 0) return null;

  return <p className="mt-3 flex items-start gap-2 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-800"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />The deadline has passed. You can still submit evidence; the inspector will see it marked as resolved late.</p>;
}
