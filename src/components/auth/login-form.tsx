"use client";

import { useState } from "react";
import Link from "next/link";
import { LoaderCircle } from "lucide-react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

export function LoginForm() {
  const router = useRouter();
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);
  async function signIn(formData: FormData) {
    setStatus(undefined); setIsPending(true);
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email: String(formData.get("email") ?? ""), password: String(formData.get("password") ?? "") });
    if (error || !data.user) { setStatus(error?.message ?? "Unable to sign in."); setIsPending(false); return; }
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", data.user.id).single();
    if (!profile) { setStatus("Your account profile is still being prepared. Please try again in a moment."); setIsPending(false); return; }
    router.replace(profile.role === "inspector" ? "/inspector" : "/owner"); router.refresh();
  }
  return <form action={signIn} className="space-y-5"><div className="space-y-2"><Label htmlFor="email">Email address</Label><Input id="email" name="email" type="email" autoComplete="email" required /></div><div className="space-y-2"><Label htmlFor="password">Password</Label><Input id="password" name="password" type="password" autoComplete="current-password" required /></div>{status && <p role="status" className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">{status}</p>}<Button className="w-full" disabled={isPending}>{isPending && <LoaderCircle className="h-4 w-4 animate-spin" />}Sign in</Button><p className="text-center text-sm text-slate-500">New to SafePlate? <Link className="font-medium text-emerald-700 hover:underline" href="/">Create an account</Link></p></form>;
}
