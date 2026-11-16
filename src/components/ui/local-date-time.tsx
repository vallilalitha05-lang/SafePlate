"use client";

/** Formats a timestamp in the viewer's own timezone (the server renders in UTC). */
export function LocalDateTime({ value, dateOnly = false }: { value: string; dateOnly?: boolean }) {
  const date = new Date(value);
  const text = dateOnly
    ? date.toLocaleDateString(undefined, { dateStyle: "medium" })
    : date.toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" });
  return <time dateTime={value} suppressHydrationWarning>{text}</time>;
}
