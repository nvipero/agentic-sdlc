# Host `supabase`

For components with `host: supabase` in `.factory/config.yaml`, in addition to the database and API items of gate `implementation`:

- every new table in an exposed schema has row level security enabled and policies that match the spec; nothing is readable or writable through a default grant (on Supabase, a new `public` table is open to every role with a grant);
- grants are explicit and minimal per role (`anon`, `authenticated`, `service_role`), and nothing the spec needs is missing a grant;
- no secret in a migration, `supabase/seed.sql` or function code (Vault or function secrets instead);
- a `security definer` function sets `search_path` and is not executable by `anon` unless the spec says so;
- an Edge Function checks its caller (JWT, or `verify_jwt` in `supabase/config.toml`) unless the spec makes it public, imports only versioned `npm:` specifiers and local files under `supabase/`, and its tests stub every external call;
- `supabase/config.toml` changes (the orchestrator passes them by line) match the spec: auth settings, redirect URLs and `verify_jwt` change who can reach what; `[functions.<name>]` settings and `[db.migrations]` reach production as merged;
- a migration that reaches outside the database (`net.http_*`, `vault.decrypted_secrets`) does what the spec needs and nothing else: it runs in production with full privileges;
- a change production's running code depends on is not removed in the same story that adds its replacement (production deploys migrations before functions and frontend).
