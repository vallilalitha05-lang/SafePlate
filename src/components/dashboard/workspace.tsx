import type { ReactNode } from "react";
import { Building2, ClipboardCheck, LogOut, MapPin, Store, UserRoundCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { AppRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { StoreLinkForm } from "@/components/dashboard/store-link-form";

async function signOut() {
  "use server";
  const supabase = await createClient();
  await supabase.auth.signOut();
}

type LinkedStore = { id: string; name: string; address: string | null };

export function Workspace({ role, name, stores = [], children }: { role: AppRole; name: string | null; stores?: LinkedStore[]; children?: ReactNode }) {
  const isInspector = role === "inspector";
  const Icon = isInspector ? ClipboardCheck : Store;
  const title = isInspector ? "Inspector workspace" : "Store owner workspace";
  const description = isInspector ? "Manage inspections and review the history for stores you inspect." : "Follow your store's inspections and prepare evidence for resolved findings.";
  return <main className="min-h-screen bg-muted/40"><header className="border-b bg-background"><div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4"><div className="flex items-center gap-3"><div className="rounded-lg bg-primary p-2 text-primary-foreground"><Icon className="h-5 w-5" /></div><span className="font-semibold">SafePlate</span><Badge>{isInspector ? "Inspector" : "Store owner"}</Badge></div><form action={signOut}><Button variant="ghost" size="sm"><LogOut className="h-4 w-4" />Sign out</Button></form></div></header><section className="mx-auto max-w-6xl px-6 py-12"><p className="text-sm font-medium text-primary">Welcome back{name ? `, ${name}` : ""}</p><h1 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h1><p className="mt-3 max-w-2xl text-muted-foreground">{description}</p><div className="mt-8 grid gap-5 md:grid-cols-3"><Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><UserRoundCheck className="h-4 w-4 text-primary" />Your access</CardTitle><CardDescription>The view shown here is determined by your registered role.</CardDescription></CardHeader><CardContent><Badge>{isInspector ? "Inspection operations" : "Your store records"}</Badge></CardContent></Card><Card><CardHeader><CardTitle className="text-base">{isInspector ? "Store history" : "Inspection history"}</CardTitle><CardDescription>{isInspector ? "Find past inspections for a selected store." : "See the inspection trail for your own store only."}</CardDescription></CardHeader></Card><Card><CardHeader><CardTitle className="text-base">Coming next</CardTitle><CardDescription>{isInspector ? "Complete a digital checklist and record the result." : "Review findings and submit proof that a fix is complete."}</CardDescription></CardHeader></Card></div>{children}{!isInspector && <div className="mt-8 grid gap-5 lg:grid-cols-[1.1fr_0.9fr]"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Building2 className="h-5 w-5 text-primary" />Linked stores</CardTitle><CardDescription>Only stores linked to your account are visible here and in future inspection views.</CardDescription></CardHeader><CardContent>{stores.length === 0 ? <div className="rounded-lg border border-dashed bg-muted/40 p-6 text-sm text-muted-foreground">No stores are linked yet. Link your first store to start managing its inspection data.</div> : <ul className="space-y-3">{stores.map((store) => <li key={store.id} className="rounded-lg border bg-background p-4"><p className="font-medium">{store.name}</p>{store.address && <p className="mt-1 flex items-center gap-1 text-sm text-muted-foreground"><MapPin className="h-3.5 w-3.5" />{store.address}</p>}</li>)}</ul>}</CardContent></Card><Card><CardHeader><CardTitle>Link a store</CardTitle><CardDescription>Add a store to your account. It will not be visible to other store owners.</CardDescription></CardHeader><CardContent><StoreLinkForm /></CardContent></Card></div>}</section></main>;
}
