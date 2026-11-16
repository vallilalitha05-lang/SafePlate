/** A joined `stores(name)` relation; Supabase returns an object for a to-one join. */
export type StoreRelation = { name: string } | { name: string }[] | null | undefined;

export function storeNameOf(stores: StoreRelation, fallback = "Your store") {
  if (!stores) return fallback;
  return (Array.isArray(stores) ? stores[0]?.name : stores.name) ?? fallback;
}
