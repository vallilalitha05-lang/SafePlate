"use client";

import { useState } from "react";
import Link from "next/link";
import { LoaderCircle } from "lucide-react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function LoginForm() {
  const router = useRouter();
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);

  async function signIn(formData: FormData) {
    const email = String(formData.get("email") ?? "").trim();
    const password = String(formData.get("password") ?? "");

    setStatus(undefined);

    // Reject malformed usernames locally. Supabase Auth receives only a validated
    // email/password payload, and its client parameterizes the authentication request.
    if (!emailPattern.test(email) || !password) {
      setStatus("Enter a valid email address and password.");
      return;
    }

    setIsPending(true);
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setStatus("Invalid email or password. Please try again.");
      setIsPending(false);
      return;
    }
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", data.user.id).single();
    if (!profile) {
      await supabase.auth.signOut();
      setStatus("Your account profile is still being prepared. Please try again in a moment.");
      setIsPending(false);
      return;
    }
    router.replace(profile.role === "inspector" ? "/inspector" : "/owner");
    router.refresh();
  }
  return <form action={signIn} className="space-y-5"><div className="space-y-2"><Label htmlFor="email">Email address</Label><Input id="email" name="email" type="email" autoComplete="email" required /></div><div className="space-y-2"><Label htmlFor="password">Password</Label><Input id="password" name="password" type="password" autoComplete="current-password" required /></div>{status && <p aria-live="assertive" role="alert" className="rounded-md border border-destructive/20 bg-destructive/10 px-3 py-2 text-sm text-destructive">{status}</p>}<Button type="submit" className="w-full" disabled={isPending}>{isPending && <LoaderCircle className="h-4 w-4 animate-spin" />}Sign in</Button><p className="text-center text-sm text-muted-foreground">New to SafePlate? <Link className="font-medium text-primary hover:underline" href="/">Create an account</Link></p></form>;
}
