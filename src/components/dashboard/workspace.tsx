import { ClipboardCheck, LogOut, Store, UserRoundCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { AppRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

async function signOut() {
  "use server";
  const supabase = await createClient();
  await supabase.auth.signOut();
}

export function Workspace({ role, name }: { role: AppRole; name: string | null }) {
  const isInspector = role === "inspector";
  const Icon = isInspector ? ClipboardCheck : Store;
  const title = isInspector ? "Inspector workspace" : "Store owner workspace";
  const description = isInspector ? "Manage inspections and review the history for stores you inspect." : "Follow your store's inspections and prepare evidence for resolved findings.";
  return <main className="min-h-screen bg-slate-50"><header className="border-b bg-white"><div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4"><div className="flex items-center gap-3"><div className="rounded-lg bg-emerald-700 p-2 text-white"><Icon className="h-5 w-5" /></div><span className="font-semibold">SafePlate</span><Badge>{isInspector ? "Inspector" : "Store owner"}</Badge></div><form action={signOut}><Button variant="ghost" size="sm"><LogOut className="h-4 w-4" />Sign out</Button></form></div></header><section className="mx-auto max-w-6xl px-6 py-12"><p className="text-sm font-medium text-emerald-700">Welcome back{name ? `, ${name}` : ""}</p><h1 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h1><p className="mt-3 max-w-2xl text-slate-600">{description}</p><div className="mt-8 grid gap-5 md:grid-cols-3"><Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><UserRoundCheck className="h-4 w-4 text-emerald-700" />Your access</CardTitle><CardDescription>The view shown here is determined by your registered role.</CardDescription></CardHeader><CardContent><Badge>{isInspector ? "Inspection operations" : "Your store records"}</Badge></CardContent></Card><Card><CardHeader><CardTitle className="text-base">{isInspector ? "Store history" : "Inspection history"}</CardTitle><CardDescription>{isInspector ? "Find past inspections for a selected store." : "See the inspection trail for your own store only."}</CardDescription></CardHeader></Card><Card><CardHeader><CardTitle className="text-base">Coming next</CardTitle><CardDescription>{isInspector ? "Create inspections, flag findings, and set remediation deadlines." : "Review findings and submit proof that a fix is complete."}</CardDescription></CardHeader></Card></div></section></main>;
}
