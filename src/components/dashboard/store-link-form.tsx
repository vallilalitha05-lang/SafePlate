"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

export function StoreLinkForm() {
  const router = useRouter();
  const [status, setStatus] = useState<string>();
  const [isPending, setIsPending] = useState(false);

  async function linkStore(formData: FormData) {
    const name = String(formData.get("name") ?? "").trim();
    const address = String(formData.get("address") ?? "").trim();

    if (name.length < 2 || name.length > 120 || address.length > 240) {
      setStatus("Enter a store name between 2 and 120 characters and a shorter address.");
      return;
    }

    setStatus(undefined);
    setIsPending(true);
    const supabase = createClient();
    const { error } = await supabase.from("stores").insert({ name, address: address || null });
    setIsPending(false);

    if (error) {
      setStatus("We could not link that store. Please try again.");
      return;
    }

    router.refresh();
  }

  return (
    <form action={linkStore} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="store-name">Store name</Label>
        <Input id="store-name" name="name" required minLength={2} maxLength={120} placeholder="Harbor Street Bakery" />
      </div>
      <div className="space-y-2">
        <Label htmlFor="store-address">Address <span className="text-muted-foreground">(optional)</span></Label>
        <Input id="store-address" name="address" maxLength={240} placeholder="125 Harbor Street" />
      </div>
      {status && <p role="alert" aria-live="assertive" className="rounded-md border border-destructive/20 bg-destructive/10 px-3 py-2 text-sm text-destructive">{status}</p>}
      <Button type="submit" disabled={isPending}>
        {isPending ? <LoaderCircle className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
        Link store
      </Button>
    </form>
  );
}
