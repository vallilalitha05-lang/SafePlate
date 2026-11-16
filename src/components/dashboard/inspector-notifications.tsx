"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, BellRing, LoaderCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LocalDateTime } from "@/components/ui/local-date-time";
import type { InspectorNotification } from "@/lib/inspector-notifications";
import { createClient } from "@/lib/supabase/client";

export function InspectorNotifications({ notifications }: { notifications: InspectorNotification[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();

  async function markRead(ids: string[] | null, key: string) {
    setBusy(key);
    setError(undefined);
    const { error: rpcError } = await createClient().rpc("mark_inspector_notifications_read", { p_ids: ids });
    if (rpcError) setError("We could not update your notifications. Please try again.");
    else router.refresh();
    setBusy(undefined);
  }

  if (notifications.length === 0) return null;
  return <Card className="border-destructive/30 bg-destructive/5">
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <CardTitle className="flex items-center gap-2 text-base"><BellRing className="h-4 w-4 text-destructive" />Notifications<span className="rounded-full bg-destructive px-2 py-0.5 text-xs text-white">{notifications.length}</span></CardTitle>
        {notifications.length > 1 && <Button type="button" size="sm" variant="ghost" onClick={() => markRead(null, "all")} disabled={busy !== undefined}>{busy === "all" && <LoaderCircle className="h-4 w-4 animate-spin" />}Mark all as read</Button>}
      </div>
      <CardDescription>The daily deadline check flagged {notifications.length === 1 ? "an issue" : `${notifications.length} issues`} on your tickets as overdue.</CardDescription>
    </CardHeader>
    <CardContent>
      <ul className="space-y-2">{notifications.map((notification) => <li key={notification.id} className="flex flex-col gap-3 rounded-md border bg-background p-3 sm:flex-row sm:items-start sm:justify-between" data-kind={notification.kind}>
        <div className="flex min-w-0 items-start gap-2 text-sm">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
          <div className="min-w-0">
            <p className="font-medium">Issue overdue</p>
            <p className="text-muted-foreground">“{notification.item}” at {notification.store} passed its remediation deadline with no evidence submitted. You can initiate suspension procedures.</p>
            <p className="mt-1 text-xs text-muted-foreground"><LocalDateTime value={notification.created_at} /></p>
          </div>
        </div>
        <Button type="button" size="sm" variant="outline" className="shrink-0 self-start" onClick={() => markRead([notification.id], notification.id)} disabled={busy !== undefined}>{busy === notification.id && <LoaderCircle className="h-4 w-4 animate-spin" />}Mark as read</Button>
      </li>)}</ul>
      {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
    </CardContent>
  </Card>;
}
