"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { BriefcaseBusiness, ClipboardCheck, LoaderCircle, Store } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

type Role = "inspector" | "store_owner";

const roles = [
  { value: "inspector" as const, title: "F&B inspector", description: "Conduct inspections and review store history.", icon: ClipboardCheck },
  { value: "store_owner" as const, title: "Store owner", description: "Track your store's inspections and resolve issues.", icon: Store },
];

export function RegisterForm() {
  const router = useRouter();
  const [role, setRole] = useState<Role>("inspector");
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);

  async function register(formData: FormData) {
    setStatus(undefined);
    setIsPending(true);
    const fullName = String(formData.get("fullName") ?? "").trim();
    const email = String(formData.get("email") ?? "").trim();
    const password = String(formData.get("password") ?? "");
    const supabase = createClient();
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName, role } },
    });
    setIsPending(false);
    if (error) { setStatus(error.message); return; }
    if (!data.session) { setStatus("Check your inbox to confirm your email, then sign in."); return; }
    router.replace(role === "inspector" ? "/inspector" : "/owner");
    router.refresh();
  }

  return (
    <form action={register} className="space-y-6">
      <div className="space-y-3">
        <Label>I am registering as</Label>
        <div className="grid gap-3 sm:grid-cols-2">
          {roles.map(({ value, title, description, icon: Icon }) => (
            <label key={value} className={cn("relative cursor-pointer rounded-lg border p-4 transition hover:border-emerald-400", role === value ? "border-emerald-600 bg-emerald-50 ring-1 ring-emerald-600" : "border-slate-200 bg-white")}>
              <input type="radio" name="role" value={value} checked={role === value} onChange={() => setRole(value)} className="sr-only" />
              <Icon className="mb-3 h-5 w-5 text-emerald-700" aria-hidden="true" />
              <p className="font-medium text-slate-900">{title}</p>
              <p className="mt-1 text-xs leading-5 text-slate-500">{description}</p>
            </label>
          ))}
        </div>
      </div>
      <div className="space-y-2"><Label htmlFor="fullName">Full name</Label><Input id="fullName" name="fullName" autoComplete="name" required minLength={2} placeholder="Jordan Lee" /></div>
      <div className="space-y-2"><Label htmlFor="email">Email address</Label><Input id="email" name="email" type="email" autoComplete="email" required placeholder="you@example.com" /></div>
      <div className="space-y-2"><Label htmlFor="password">Password</Label><Input id="password" name="password" type="password" autoComplete="new-password" required minLength={8} placeholder="At least 8 characters" /><p className="text-xs text-slate-500">Use at least 8 characters.</p></div>
      {status && <p role="status" className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">{status}</p>}
      <Button type="submit" className="w-full" disabled={isPending}>{isPending && <LoaderCircle className="h-4 w-4 animate-spin" />}Create account</Button>
      <p className="text-center text-xs text-slate-500">Your role determines the workspace and records you can access.</p>
      <p className="text-center text-sm text-slate-500">Already registered? <Link className="font-medium text-emerald-700 hover:underline" href="/login">Sign in</Link></p>
    </form>
  );
}
