import Link from "next/link";
import { ArrowRight, History } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

type DirectoryStore = { id: string; name: string; address: string | null; operating_status?: string };

/** Every store, linking to its full inspection history. */
export function StoreDirectory({ stores }: { stores: DirectoryStore[] }) {
  return <Card>
    <CardHeader><CardTitle className="flex items-center gap-2"><History className="h-5 w-5 text-primary" />Store history</CardTitle><CardDescription>Review any store&apos;s past inspections, violations and trends before a new inspection.</CardDescription></CardHeader>
    <CardContent>
      {stores.length === 0
        ? <p className="text-sm text-muted-foreground">No stores have been linked yet.</p>
        : <ul className="divide-y rounded-lg border bg-background">{stores.map((store) => <li key={store.id}>
            <Link href={`/inspector/stores/${store.id}`} className="flex items-center justify-between gap-3 px-4 py-3 hover:bg-muted/60">
              <span className="min-w-0"><span className="flex items-center gap-2 font-medium">{store.name}{store.operating_status === "suspended" && <Badge variant="destructive">Suspended</Badge>}</span>{store.address && <span className="block truncate text-sm text-muted-foreground">{store.address}</span>}</span>
              <span className="inline-flex shrink-0 items-center gap-1 text-sm font-medium text-primary">View history<ArrowRight className="h-4 w-4" /></span>
            </Link>
          </li>)}</ul>}
    </CardContent>
  </Card>;
}
