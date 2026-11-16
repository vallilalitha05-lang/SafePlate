import type { ReactNode } from "react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowRight, BellRing, ListOrdered, Building2, ClipboardCheck, ImageIcon, LogOut, MapPin, Store, TicketCheck, UserRoundCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { AppRole } from "@/lib/auth";
import type { FlaggedItem } from "@/lib/evidence";
import { compareByDeadline, needsAction, settledLabel, sortByDeadline } from "@/lib/deadlines";
import { DeadlineBadge } from "@/components/dashboard/deadline-badge";
import { ItemStatusBadges, ReviewOutcome } from "@/components/dashboard/item-status";
import { createClient } from "@/lib/supabase/server";
import { StoreLinkForm } from "@/components/dashboard/store-link-form";

async function signOut() {
  "use server";
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

type LinkedStore = { id: string; name: string; address: string | null };
type RemediationTicket = {
  id: string;
  status: string;
  flagged_items: FlaggedItem[];
  created_at: string;
  stores: { name: string }[] | null;
};
type TicketNotification = { id: string; ticket_id: string; created_at: string };

export function Workspace({ role, name, stores = [], tickets = [], notifications = [], photoUrls = {}, children }: { role: AppRole; name: string | null; stores?: LinkedStore[]; tickets?: RemediationTicket[]; notifications?: TicketNotification[]; photoUrls?: Record<string, string>; children?: ReactNode }) {
  const isInspector = role === "inspector";
  const priorities = tickets
    .filter((ticket) => ticket.status === "open")
    .flatMap((ticket) => ticket.flagged_items.filter(needsAction).map((item) => ({ ticketId: ticket.id, store: ticket.stores?.[0]?.name ?? "Your store", item })))
    .sort((a, b) => compareByDeadline(a.item, b.item));
  const Icon = isInspector ? ClipboardCheck : Store;
  const title = isInspector ? "Inspector workspace" : "Store owner workspace";
  const description = isInspector ? "Run inspections, review evidence store owners submit, and decide whether flagged issues are resolved." : "Follow your store's inspections and prepare evidence for resolved findings.";

  return <main className="min-h-screen bg-muted/40">
    <header className="border-b bg-background"><div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4"><div className="flex items-center gap-3"><div className="rounded-lg bg-primary p-2 text-primary-foreground"><Icon className="h-5 w-5" /></div><span className="font-semibold">SafePlate</span><Badge>{isInspector ? "Inspector" : "Store owner"}</Badge></div><form action={signOut}><Button variant="ghost" size="sm"><LogOut className="h-4 w-4" />Sign out</Button></form></div></header>
    <section className="mx-auto max-w-6xl px-6 py-12">
      <p className="text-sm font-medium text-primary">Welcome back{name ? `, ${name}` : ""}</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-3 max-w-2xl text-muted-foreground">{description}</p>
      <div className="mt-8 grid gap-5 md:grid-cols-3"><Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><UserRoundCheck className="h-4 w-4 text-primary" />Your access</CardTitle><CardDescription>The view shown here is determined by your registered role.</CardDescription></CardHeader><CardContent><Badge>{isInspector ? "Inspection operations" : "Your store records"}</Badge></CardContent></Card><Card><CardHeader><CardTitle className="text-base">{isInspector ? "Store history" : "Inspection history"}</CardTitle><CardDescription>{isInspector ? "Find past inspections for a selected store." : "See the inspection trail for your own store only."}</CardDescription></CardHeader></Card><Card><CardHeader><CardTitle className="text-base">Coming next</CardTitle><CardDescription>{isInspector ? "Complete a digital checklist and record the result." : "Open a ticket to upload photo evidence that each flagged issue is fixed."}</CardDescription></CardHeader></Card></div>
      {children}
      {!isInspector && <div className="mt-8 space-y-5">
        {notifications.length > 0 && <Card className="border-primary/30 bg-primary/5"><CardHeader><CardTitle className="flex items-center gap-2 text-base"><BellRing className="h-4 w-4 text-primary" />New inspection ticket{notifications.length === 1 ? "" : "s"}</CardTitle><CardDescription>{notifications.length === 1 ? "A new remediation ticket has been issued for one of your stores." : `${notifications.length} remediation tickets have been issued for your stores.`}</CardDescription></CardHeader></Card>}
        {priorities.length > 0 && <Card><CardHeader><CardTitle className="flex items-center gap-2"><ListOrdered className="h-5 w-5 text-primary" />Fix priorities</CardTitle><CardDescription>Every issue still waiting for a fix, soonest remediation deadline first. Fix these before their deadlines to avoid penalties.</CardDescription></CardHeader><CardContent><ol className="space-y-3">{priorities.map(({ ticketId, store, item }, index) => <li key={`${ticketId}-${item.item}`} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-background p-3"><div className="flex min-w-0 items-start gap-3"><span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">{index + 1}</span><div className="min-w-0"><p className="font-medium">{item.item}</p><p className="text-sm text-muted-foreground">{store}</p><DeadlineBadge className="mt-2" deadline={item.remediation_deadline} /></div></div><Link href={`/owner/tickets/${ticketId}`} className="inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline">Upload evidence<ArrowRight className="h-4 w-4" /></Link></li>)}</ol></CardContent></Card>}
        <Card><CardHeader><CardTitle className="flex items-center gap-2"><TicketCheck className="h-5 w-5 text-primary" />Remediation tickets</CardTitle><CardDescription>New tickets are delivered here automatically when an inspection identifies failed items.</CardDescription></CardHeader><CardContent>{tickets.length === 0 ? <div className="rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground">No remediation tickets have been issued for your stores.</div> : <ul className="space-y-3">{tickets.map((ticket) => <li key={ticket.id} className="rounded-lg border bg-background p-4"><div className="flex flex-wrap items-center justify-between gap-2"><p className="font-medium">{ticket.stores?.[0]?.name ?? "Your store"}</p><Badge>{ticket.status}</Badge></div><p className="mt-1 text-sm text-muted-foreground">Issued {new Date(ticket.created_at).toLocaleDateString()}</p><ul className="mt-4 space-y-3">{sortByDeadline(ticket.flagged_items).map((item) => <li key={item.item} className="rounded-md bg-muted/60 p-3"><div className="flex flex-wrap items-start justify-between gap-2"><p className="font-medium">{item.item}</p>{item.status && <ItemStatusBadges item={item} />}</div><p className="mt-1 text-sm text-muted-foreground">{item.comment}</p><DeadlineBadge className="mt-2" deadline={item.remediation_deadline} settled={settledLabel(item)} /><ReviewOutcome item={item} />{item.photo_path && photoUrls[item.photo_path] && <a className="mt-3 inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline" href={photoUrls[item.photo_path]} target="_blank" rel="noreferrer"><ImageIcon className="h-4 w-4" />View inspection photo</a>}</li>)}</ul>{ticket.status === "open" && <Link href={`/owner/tickets/${ticket.id}`} className="mt-4 inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline">Upload evidence of fixes<ArrowRight className="h-4 w-4" /></Link>}</li>)}</ul>}</CardContent></Card>
        <div className="grid gap-5 lg:grid-cols-[1.1fr_0.9fr]"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Building2 className="h-5 w-5 text-primary" />Linked stores</CardTitle><CardDescription>Only stores linked to your account are visible here and in future inspection views.</CardDescription></CardHeader><CardContent>{stores.length === 0 ? <div className="rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground">No stores are linked yet. Link your first store to start managing its inspection data.</div> : <ul className="space-y-3">{stores.map((store) => <li key={store.id} className="rounded-lg border bg-background p-4"><p className="font-medium">{store.name}</p>{store.address && <p className="mt-1 flex items-center gap-1 text-sm text-muted-foreground"><MapPin className="h-3.5 w-3.5" />{store.address}</p>}</li>)}</ul>}</CardContent></Card><Card><CardHeader><CardTitle>Link a store</CardTitle><CardDescription>Add a store to your account. It will not be visible to other store owners.</CardDescription></CardHeader><CardContent><StoreLinkForm /></CardContent></Card></div>
      </div>}
    </section>
  </main>;
}
