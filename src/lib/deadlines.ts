import type { FlaggedItem } from "@/lib/evidence";

export const dueSoonDays = 3;

export type DeadlineUrgency = "overdue" | "today" | "soon" | "upcoming" | "none";

const isoDate = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Parses a YYYY-MM-DD deadline as a calendar date (no timezone shift). */
function toUtcDay(deadline: string) {
  const match = isoDate.exec(deadline);
  if (!match) return null;
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

export function localToday(now = new Date()) {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

/** Whole days from `today` until `deadline`; negative when overdue. */
export function daysUntil(deadline: string | null, today: string) {
  if (!deadline) return null;
  const due = toUtcDay(deadline);
  const start = toUtcDay(today);
  if (due === null || start === null) return null;
  return Math.round((due - start) / 86_400_000);
}

export function deadlineUrgency(days: number | null): DeadlineUrgency {
  if (days === null) return "none";
  if (days < 0) return "overdue";
  if (days === 0) return "today";
  if (days <= dueSoonDays) return "soon";
  return "upcoming";
}

export function describeCountdown(days: number | null) {
  if (days === null) return "No deadline set";
  if (days < 0) return `Overdue by ${-days} day${days === -1 ? "" : "s"}`;
  if (days === 0) return "Due today";
  if (days === 1) return "Due tomorrow";
  return `Due in ${days} days`;
}

/** Formats a YYYY-MM-DD deadline, e.g. "Fri, Nov 20, 2026", without timezone drift. */
export function formatDeadline(deadline: string | null) {
  if (!deadline) return "No deadline set";
  const day = toUtcDay(deadline);
  if (day === null) return deadline;
  return new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric", timeZone: "UTC" }).format(new Date(day));
}

/** An item needs the owner's action until evidence is submitted or the inspector resolves it. */
export function needsAction(item: FlaggedItem) {
  return item.status !== "pending_inspector_review" && item.status !== "resolved";
}

/** Label shown instead of a countdown once the owner no longer needs to act. */
export function settledLabel(item: FlaggedItem) {
  if (item.status === "resolved") return "Resolved";
  if (item.status === "pending_inspector_review") return "Evidence submitted";
  return undefined;
}

/** Items needing action first, then by earliest deadline; items without a deadline last. */
export function compareByDeadline(a: FlaggedItem, b: FlaggedItem) {
  if (needsAction(a) !== needsAction(b)) return needsAction(a) ? -1 : 1;
  const left = a.remediation_deadline ?? "9999-12-31";
  const right = b.remediation_deadline ?? "9999-12-31";
  return left.localeCompare(right) || a.item.localeCompare(b.item);
}

export function sortByDeadline(items: FlaggedItem[]) {
  return [...items].sort(compareByDeadline);
}
