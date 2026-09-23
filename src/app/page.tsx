import { BriefcaseBusiness, CheckCircle2, ShieldCheck } from "lucide-react";
import { RegisterForm } from "@/components/auth/register-form";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function Home() {
  return (
    <main className="min-h-screen bg-muted/40 px-4 py-8 sm:px-6 lg:px-8">
      <div className="mx-auto grid max-w-6xl overflow-hidden rounded-2xl border bg-card shadow-xl shadow-primary/10 lg:grid-cols-[1.05fr_0.95fr]">
        <section className="bg-primary px-7 py-10 text-primary-foreground sm:px-12 lg:py-16">
          <div className="flex items-center gap-2"><BriefcaseBusiness className="h-6 w-6" /><span className="text-lg font-semibold tracking-tight">SafePlate</span></div>
          <Badge className="mt-14 bg-primary-foreground/15 text-primary-foreground" variant="secondary">F&B inspection workspace</Badge>
          <h1 className="mt-5 max-w-md text-4xl font-semibold tracking-tight sm:text-5xl">Make food safety follow-through clear.</h1>
          <p className="mt-5 max-w-lg text-base leading-7 text-primary-foreground/75">A shared workspace for inspectors and store owners, designed to keep inspections, findings, and fixes moving.</p>
          <ul className="mt-12 space-y-5 text-sm text-primary-foreground/90">
            <li className="flex gap-3"><CheckCircle2 className="h-5 w-5 shrink-0 text-primary-foreground" />Inspectors can review inspection work and store history.</li>
            <li className="flex gap-3"><CheckCircle2 className="h-5 w-5 shrink-0 text-primary-foreground" />Store owners see only the records for their own store.</li>
            <li className="flex gap-3"><ShieldCheck className="h-5 w-5 shrink-0 text-primary-foreground" />Role access is enforced in the database, not just the interface.</li>
          </ul>
        </section>
        <section className="px-6 py-10 sm:px-12 lg:py-14">
          <Card className="border-0 shadow-none"><CardHeader className="px-0 pt-0"><CardTitle className="text-2xl">Create your account</CardTitle><CardDescription>Choose the role that matches how you work with inspections.</CardDescription></CardHeader><CardContent className="px-0 pb-0"><RegisterForm /></CardContent></Card>
        </section>
      </div>
    </main>
  );
}
