import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AppRole = "inspector" | "store_owner";

export async function getViewer() {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) redirect("/");

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, role")
    .eq("id", userId)
    .single();

  if (!profile || (profile.role !== "inspector" && profile.role !== "store_owner")) redirect("/");
  return profile as { full_name: string | null; role: AppRole };
}
