# SafePlate - F&B Inspection App

Implements the Project 1 **Account & Access** story: people register as either an F&B inspector or store owner and land in a role-specific workspace.

## Local setup

1. Create a Supabase project and run [`supabase/schema.sql`](supabase/schema.sql) in its SQL editor.
2. Copy `.env.example` to `.env.local`, then add the project URL and **publishable** key from Supabase Connect.
3. Run `pnpm install` and `pnpm dev`.

The schema uses RLS to limit profile reads to the authenticated person. It deliberately has no browser-writable role policy, so roles cannot be escalated client-side after registration.

## Deployment

Add the same two `NEXT_PUBLIC_SUPABASE_*` variables to Vercel, then deploy the repository. No service-role key is used by this app.
