"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Ban, BellRing, CalendarClock, CheckCircle2, LoaderCircle, ShieldCheck, TicketCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LocalDateTime } from "@/components/ui/local-date-time";
import { describeNotification, type NotificationView } from "@/lib/notifications";
import { createClient } from "@/lib/supabase/client";

export function OwnerNotifications({ notifications }: { notifications: NotificationView[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();

  async function markRead(ids: string[] | null, key: string) {
    setBusy(key);
    setError(undefined);
    const { error: rpcError } = await createClient().rpc("mark_owner_notifications_read", { p_ids: ids });
    if (rpcError) setError("We could not update your notifications. Please try again.");
    else router.refresh();
    setBusy(undefined);
  }

  if (notifications.length === 0) return null;
  const approvals = notifications.filter((notification) => notification.kind === "item_approved").length;
  const rejections = notifications.filter((notification) => notification.kind === "item_rejected").length;

  return <Card className="border-primary/30 bg-primary/5">
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <CardTitle className="flex items-center gap-2 text-base"><BellRing className="h-4 w-4 text-primary" />Notifications<span className="rounded-full bg-primary px-2 py-0.5 text-xs text-primary-foreground">{notifications.length}</span></CardTitle>
        {notifications.length > 1 && <Button type="button" size="sm" variant="ghost" onClick={() => markRead(null, "all")} disabled={busy !== undefined}>{busy === "all" && <LoaderCircle className="h-4 w-4 animate-spin" />}Mark all as read</Button>}
      </div>
      <CardDescription>{[approvals > 0 && `${approvals} fix${approvals === 1 ? " was" : "es were"} approved`, rejections > 0 && `${rejections} fix${rejections === 1 ? " was" : "es were"} rejected with a follow-up inspection scheduled`].filter(Boolean).join(" · ") || "Updates about inspections at your stores."}</CardDescription>
    </CardHeader>
    <CardContent>
      <ul className="space-y-2">{notifications.map((notification) => {
        const { title, message, reason, scheduledFor } = describeNotification(notification);
        const approved = notification.kind === "item_approved";
        const rejected = notification.kind === "item_rejected";
        const suspended = notification.kind === "store_suspended";
        const lifted = notification.kind === "suspension_lifted";
        const Icon = approved ? CheckCircle2 : rejected ? CalendarClock : suspended ? Ban : lifted ? ShieldCheck : TicketCheck;
        return <li key={notification.id} className="flex flex-col gap-3 rounded-md border bg-background p-3 sm:flex-row sm:items-start sm:justify-between" data-kind={notification.kind}>
          <div className="flex min-w-0 items-start gap-2">
            <Icon className={`mt-0.5 h-4 w-4 shrink-0 ${approved || lifted ? "text-emerald-600" : rejected ? "text-amber-600" : suspended ? "text-destructive" : "text-primary"}`} />
            <div className="min-w-0 text-sm">
              <p className="font-medium">{title}</p>
              <p className="text-muted-foreground">{message}</p>
              {reason && <p className="mt-1"><span className="font-medium">Reason:</span> “{reason}”</p>}
              {scheduledFor && <p className="mt-1"><span className="font-medium">Follow-up inspection:</span> <LocalDateTime value={scheduledFor} /></p>}
              <p className="mt-1 text-xs text-muted-foreground"><LocalDateTime value={notification.created_at} />{notification.ticket_id && <> · <Link className="font-medium text-primary underline-offset-4 hover:underline" href={`/owner/tickets/${notification.ticket_id}`}>View ticket</Link></>}</p>
            </div>
          </div>
          <Button type="button" size="sm" variant="outline" className="shrink-0 self-start" onClick={() => markRead([notification.id], notification.id)} disabled={busy !== undefined}>{busy === notification.id && <LoaderCircle className="h-4 w-4 animate-spin" />}Mark as read</Button>
        </li>;
      })}</ul>
      {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
    </CardContent>
  </Card>;
}
