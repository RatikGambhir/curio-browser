# Plan: profiles, accounts and integrations

Status: draft, 2026-10-28. Nothing here is built yet. This replaces the
earlier sign-in-only plan.

## Goals

1. **Local profiles like Arc's.** Each profile has its own cookies, logins,
   history and spaces, so "Work" and "Personal" stay apart. No account is
   needed.
2. **Sign in with Apple stays on the Mac.** It labels a local profile with your
   Apple identity. It never creates a server account.
3. **Curio accounts through Google or Microsoft.** Signing in with either one
   creates (or signs in to) an account on `curio-server`. One account can have
   both Google and Microsoft attached.
4. **Integrations.** A signed-in profile can connect Google and Microsoft data
   sources. The first two are **Gmail (read mail)** and **OneNote (read
   notes)**. The design makes adding the next one (Calendar, Drive, Outlook,
   OneDrive…) a small, mechanical change. Section 9 gives the recipe.

## Terms

| Term | Lives in | Meaning |
|------|----------|---------|
| **Profile** | App (SQLite) | A local browsing identity: name, colour, icon, its own WebKit data store, its own spaces |
| **Local identity** | App | Optional Sign in with Apple identity attached to a profile (name, email, Apple user ID) |
| **Account** | Server | A Curio user. Created by the first Google or Microsoft sign-in |
| **Identity** | Server | A way to sign in to an account: (Google, `sub`) or (Microsoft, `oid`/`sub`). An account can have several |
| **Connection** | Server | A granted permission to a provider account's data, holding an encrypted refresh token and its scopes. It can be a different Google or Microsoft account from the one you sign in with |
| **Connector** | Server + app | A kind of integration (`gmail`, `onenote`), defined by its provider, scopes and the code that reads its data |

A profile links to **at most one** account. The same account can be linked to
profiles on several Macs.

---

## 1. What you need to provide

Placeholders for all of these are listed in section 8. None of the secrets
(client secrets, encryption key, database URL) ever go in the repo.

### Google (Google Cloud Console)

| # | Item | Notes |
|---|------|-------|
| G1 | A Google Cloud project | console.cloud.google.com |
| G2 | **OAuth consent screen**: app name, support email, logo, home page, **privacy policy URL**, **terms URL**, authorised domain (your server's domain) | APIs & Services → OAuth consent screen, user type *External* |
| G3 | **OAuth client ID of type Web application** → **Client ID** and **Client secret** | Credentials → Create OAuth client ID → *Web application*. The server is the OAuth client now, so this is a Web client (not the iOS type from the old plan) |
| G4 | **Authorised redirect URIs** on that client: `http://localhost:8080/v1/auth/google/callback` (development) and `https://<your-server-domain>/v1/auth/google/callback` (production) | |
| G5 | **Gmail API enabled** in the project | APIs & Services → Library → Gmail API |
| G6 | **Test users** (up to 100 Google accounts) while the app is unverified | OAuth consent screen → Test users |
| G7 | Later, before public launch: **Google app verification** for the restricted Gmail scope, including the yearly **CASA security assessment** | See risk R1. Plan weeks for this, and budget for it |

Scopes: sign-in uses `openid email profile`, which are non-sensitive. Gmail uses
`https://www.googleapis.com/auth/gmail.readonly`, which is **restricted**.

### Microsoft (Microsoft Entra admin center)

| # | Item | Notes |
|---|------|-------|
| M1 | **App registration** "Curio" → **Application (client) ID** | entra.microsoft.com → App registrations |
| M2 | Supported account types: **personal + work/school** (tenant `common`) | Recommended. OneNote works for both |
| M3 | Platform **Web**, with redirect URIs `http://localhost:8080/v1/auth/microsoft/callback` and `https://<your-server-domain>/v1/auth/microsoft/callback` | Authentication → Add a platform → Web |
| M4 | **Client secret** → its **value**, and note the **expiry date** (24 months at most) | Certificates & secrets |
| M5 | **API permissions** (delegated, Microsoft Graph): `openid`, `email`, `profile`, `offline_access`, `User.Read`, `Notes.Read` | API permissions → Add → Microsoft Graph → Delegated |
| M6 | Later: **publisher verification**, so consent screens don't say "unverified" | Needs a Microsoft Partner Network ID |

### Apple (local only)

| # | Item | Notes |
|---|------|-------|
| A1 | **Apple Developer Program** membership ($99/year) | Sign in with Apple can't be used without it |
| A2 | **Team ID** | developer.apple.com → Membership |
| A3 | **App ID** `app.curio.browser` with **Sign in with Apple** enabled | Identifiers |
| A4 | Signing certificate: **Apple Development** (testing) and **Developer ID Application** (release) | Xcode → Settings → Accounts |
| A5 | **Provisioning profiles** (development + Developer ID) for `app.curio.browser` with Sign in with Apple, and your Mac's Provisioning UDID registered for the development one | Profiles |

No Services ID, `.p8` key or return URL is needed, because Apple never goes
through the server.

### Server and hosting

| # | Item | Notes |
|---|------|-------|
| S1 | **A domain** for the API, for example `api.<yourdomain>` with HTTPS | Google and Microsoft only accept `https` redirect URIs outside `localhost` |
| S2 | **Hosting** for the Axum service (Fly.io, Render, Railway, a VPS…) | It's a single small binary. A Dockerfile comes in phase 9 |
| S3 | **PostgreSQL** database → `DATABASE_URL` | Managed Postgres from the host, or Neon or Supabase. For development, Docker locally |
| S4 | **Token encryption key**: 32 random bytes, base64 → `CURIO_TOKEN_KEY` | `openssl rand -base64 32`. Stored only in the host's secret settings |
| S5 | Privacy policy and terms pages at stable URLs | Google requires them, and the restricted-scope review reads them closely |

### Assets

Official sign-in button marks for Apple, Google and Microsoft go in
`browser/assets/auth/`. Each provider publishes branding rules for its button.

---

## 2. Decisions

| ID | Question | Recommendation |
|----|----------|----------------|
| D1 | **Minimum macOS.** Separate data per profile needs `WKWebsiteDataStore(forIdentifier:)`, which is macOS 14+. On macOS 13, wry silently uses the shared store, so profiles would share cookies. | Raise `LSMinimumSystemVersion` from 13.0 to **14.0** in `browser/script/bundle-macos.sh` |
| D2 | **Where integration data is read.** (a) The app calls Gmail and Graph directly with short-lived access tokens the server hands out, so mail and notes never pass through Curio's server. (b) The server fetches, and may cache or index, the data. | **(a) for now.** It's simpler, more private and cheaper to run. The connector design allows (b) per connector later, for background sync or alerts. Whether (a) narrows Google's security assessment has to be confirmed with Google during verification (R1) |
| D3 | Connecting Gmail from a profile with **no account** (local or Apple-only) | It runs "Sign in with Google" with the extra scopes in one step, creating the account and the connection together |
| D4 | Is an account required at first launch? | **No.** The first-run screen offers Google, Microsoft, Apple, or "Continue without an account". Each of them creates the first profile |
| D5 | Are AI provider API keys per profile or shared? | **Shared** (no change) for now |
| D6 | Session lifetime | Access token 1 hour, refresh token 60 days and rotated on each use, both opaque and stored hashed |

---

## 3. Architecture

```
┌──────────────────────────── browser/ (macOS app) ─────────────────────────────┐
│ Profile ── WKWebsiteDataStore(uuid) ── spaces, tabs, history, bookmarks       │
│   ├─ local_identity: Option<AppleIdentity>        ← ASAuthorizationAppleID…   │
│   └─ account: Option<AccountLink> ── session tokens in Keychain (per profile) │
│                                                                               │
│ curio-account   server client, auth sheet bridge, Apple bridge                │
│ curio-connectors Gmail / OneNote readers → curio-ai context sources           │
└──────────────┬────────────────────────────────────────────────────────────────┘
               │ HTTPS JSON (types shared via curio-api)
┌──────────────▼──────────── curio-server/ (Axum) ──────────────────────────────┐
│ /v1/auth/*         sign in with Google / Microsoft, sessions                  │
│ /v1/me             account, identities, delete account                        │
│ /v1/connections/*  connect / list / disconnect / mint access token            │
│ providers/   OAuthProvider trait: google.rs, microsoft.rs                     │
│ connectors/  registry: gmail, onenote (scopes + data-access mode)             │
│ Postgres: users, identities, connections, sessions, auth_requests, grants     │
└──────────────┬────────────────────────────────────────────────────────────────┘
               │ OAuth 2.0 / OIDC (server is a confidential client + PKCE)
        accounts.google.com · login.microsoftonline.com · Gmail API · Microsoft Graph
```

---

## 4. Local profiles (app only)

**Model.** There's a new `profiles` table in the app database
(`browser/crates/curio-storage/src/migrations.rs`):

```sql
CREATE TABLE profiles (
    id             TEXT PRIMARY KEY,        -- uuid
    name           TEXT NOT NULL,
    icon           TEXT,                    -- emoji or symbol name
    color          TEXT NOT NULL,           -- reuses curio-core accent palette
    data_store_id  BLOB NOT NULL,           -- 16-byte uuid for WKWebsiteDataStore
    apple_identity TEXT,                    -- JSON: {user_id, name, email} (section 5)
    account_json   TEXT,                    -- JSON: {user_id, email, display_name} (section 6)
    position       INTEGER NOT NULL,
    created_at     INTEGER NOT NULL
);
```

- `spaces` gets a `profile_id` column, like Arc, where each space belongs to a
  profile. Tabs follow their space.
- `history`, `bookmarks`, `downloads`, `site_permissions` and `conversations`
  get a `profile_id` column too. The migration creates a **"Default"** profile
  and assigns all existing rows to it, so current users lose nothing.
- The settings table stays global.

**Engine.** `browser/crates/curio-browser/src/engine.rs` (the
`WebViewBuilder` at about line 59) calls
`.with_data_store_identifier(profile.data_store_id)` for every webview.
Deleting a profile calls wry's `remove_data_store`.

**Keychain.** Account names are namespaced per profile:
`profile.<id>.session.refresh`. API keys stay global (D5).

**UI** (`browser/crates/curio-ui`):
- **Profile switcher** in the sidebar's space switcher. It shows the active
  profile's icon, and the menu lists profiles plus **New Profile…**.
- **New Profile** dialog: name, icon and colour, then *Continue with Google /
  Microsoft / Apple* or *Skip*.
- **Settings → Profiles**: rename, recolour, delete (with a confirmation that
  says its browsing data is erased), and sign in or out per profile.
- **First run**: if no profile exists, show the welcome screen (D4) instead of
  the browser window.

**Development escape hatch:** `CURIO_SKIP_ONBOARDING=1` creates a Default
profile and goes straight to the browser.

---

## 5. Sign in with Apple (local only)

1. `ASAuthorizationAppleIDProvider().createRequest()` with scopes
   `[.fullName, .email]` and a hashed nonce, run through
   `ASAuthorizationController` anchored to the window.
2. Verify `identityToken` **on the device** against
   `https://appleid.apple.com/auth/keys`. Check `iss = https://appleid.apple.com`,
   `aud = app.curio.browser`, the nonce and `exp`.
3. Save `{user_id, name, email}` to `profiles.apple_identity` immediately.
   Apple only sends the name and email on the **first** authorisation.
4. On launch, `getCredentialState(forUserID:)`. If it returns `.revoked` or
   `.notFound`, clear the identity. The profile and its browsing data stay.
5. Discard `authorizationCode`, since nothing redeems it.

Apple sign-in needs a signed, provisioned `.app` (section 8). It never works
under plain `cargo run`.

---

## 6. Curio accounts: sign in with Google or Microsoft

The **server** is the OAuth client: it holds the client secrets and the
providers' refresh tokens. The app never sees a provider secret or refresh
token. It only gets **Curio** session tokens.

### Flow (backend-for-frontend, with PKCE on both legs)

```
App                                 curio-server                        Google / Microsoft
 │ app_verifier, app_challenge         │                                      │
 │ ASWebAuthenticationSession ────────►│ GET /v1/auth/{p}/start               │
 │   (callback scheme curio-auth)      │   ?intent=signin&app_challenge=…     │
 │                                     │ save auth_request{state, nonce,      │
 │                                     │   provider_verifier, app_challenge}  │
 │                                     │ 302 ────────────────────────────────►│ consent
 │                                     │◄──────────── GET /v1/auth/{p}/callback?code&state
 │                                     │ exchange code (+secret, +verifier)   │
 │                                     │ verify id_token (JWKS, iss, aud,     │
 │                                     │   nonce, exp)                        │
 │                                     │ upsert user + identity               │
 │                                     │ create one-time grant (60 s)         │
 │◄──── 302 curio-auth://callback?grant=…                                     │
 │ POST /v1/auth/token {grant, app_verifier} ─►│ check SHA256(verifier) =      │
 │◄──── {access_token, refresh_token, account}  │   app_challenge; burn grant   │
```

- **Why PKCE between the app and the server:** another app could register the
  `curio-auth://` scheme and catch the redirect. Without `app_verifier` the
  grant is useless to it.
- **Why `ASWebAuthenticationSession`:** it's Apple's supported web sign-in
  sheet. It isn't Curio's own WKWebView, which Google blocks with
  `disallowed_useragent`. It also avoids the sign-in opening in a Curio tab
  when Curio is the default browser.
- **Microsoft issuer:** with tenant `common`, the `iss` is
  `https://login.microsoftonline.com/{tid}/v2.0`. Check it with the token's own
  `tid` claim. Use `oid` + `tid` (not `email`) as the stable identity key.
- **Linking accounts:** a signed-in user can add the other provider in Settings
  → Account → *Add sign-in method*. This is the same flow with
  `intent=link`, which needs a session. An identity already attached to a
  different account is rejected with a clear message. It is never merged
  silently.
- **Sign-in identities store no provider tokens.** They prove who you are and
  nothing more. Provider tokens live only on connections (section 7).

### Sessions

- `POST /v1/auth/token` with `grant_type=refresh_token` rotates the refresh
  token. Reusing an old one revokes the whole session (theft detection).
- `POST /v1/auth/logout` revokes the session.
- The app stores the refresh token in the Keychain per profile, and keeps the
  access token in memory. If it's offline at launch, the profile stays signed
  in and server features show "Offline".

---

## 7. Integrations (connections and connectors)

### Connect flow

1. The app (signed in) calls `POST /v1/connections` with
   `{connector: "gmail", app_challenge}` →
   `{authorize_url}`. The URL points at
   `/v1/auth/google/start?request=<auth_request id>`, and the auth request is
   bound to the user.
2. The app opens `authorize_url` in `ASWebAuthenticationSession`. The server
   asks Google for the connector's scopes with `access_type=offline`,
   `prompt=consent`, `include_granted_scopes=true`, and `login_hint` set to the
   user's email (the user can pick a different Google account).
3. On the callback, the server stores a **connection**: provider, provider
   account `sub`, email, granted scopes, and the **AES-256-GCM-encrypted
   refresh token**. It then redirects to `curio-auth://callback?grant=…` and the
   app redeems the grant for the connection's details.
4. If the profile had no account (D3), steps 1–3 run with `intent=signin`
   plus the connector's scopes, and they create the account and the connection
   together.

### Reading data (D2 option a: through the app)

- `POST /v1/connections/{id}/access-token` → `{access_token, expires_at, scopes}`.
  The server refreshes with the provider as needed and caches nothing in plain
  text. The app keeps the token in memory only.
- `browser/crates/curio-connectors` calls the provider API directly:
  - **Gmail** (`gmail.readonly`):
    `GET https://gmail.googleapis.com/gmail/v1/users/me/messages?q=…`,
    then `…/messages/{id}?format=full`, which is MIME parsed to plain text.
  - **OneNote** (`Notes.Read`):
    `GET https://graph.microsoft.com/v1.0/me/onenote/notebooks`, `…/sections`,
    `…/pages`, and `…/pages/{id}/content`, whose HTML is converted to text.
- Each connector exposes a **context source** to `curio-ai`, the same way page
  context works today. The assistant can then say "Use my email" or "Search my
  OneNote" with visible chips, and nothing is sent to the AI provider without
  those chips.

### Managing connections

- `GET /v1/connections`: list them with status (`active`, `needs_reauth` when
  the provider returns `invalid_grant`, or `revoked`).
- `DELETE /v1/connections/{id}`: revoke at the provider where possible (Google
  has a revoke endpoint; Microsoft has no per-token revoke, so delete the
  token and link the user to account.microsoft.com → Privacy → Apps), then
  delete the row.
- **Settings → Integrations** in the app lists each connector, which account
  it's connected to, and **Connect / Reconnect / Disconnect** buttons.

### Account deletion

`DELETE /v1/me` revokes every connection, deletes all rows and ends all
sessions. Google's policy requires it, and so does App Store review if Curio
ever ships there.

---

## 8. Code layout, placeholders and configuration

### Server

```
curio-server/
├── Cargo.toml              becomes a workspace: members [".", "api"]
├── api/                    curio-api: request/response types (serde only, no axum)
│                           shared with the app via a path dependency
├── migrations/             sqlx migrations
├── .env.example            every variable below, with placeholders
└── src/
    ├── main.rs             (exists) startup, shutdown
    ├── app.rs              (exists) router, layers, /health
    ├── config.rs           env → typed Config; fails fast on missing values
    ├── error.rs            AppError → JSON {error, message}
    ├── db.rs               PgPool, migrations at startup
    ├── crypto.rs           AES-256-GCM seal/open with key id; token hashing
    ├── auth/
    │   ├── routes.rs       start, callback, token, logout
    │   ├── requests.rs     auth_requests + grants (single use, expiring)
    │   ├── sessions.rs     issue, rotate, revoke; extractor `CurrentUser`
    │   └── id_token.rs     JWKS cache + verification
    ├── providers/
    │   ├── mod.rs          trait OAuthProvider + ProviderId
    │   ├── google.rs
    │   └── microsoft.rs
    ├── connectors/
    │   ├── mod.rs          Connector registry
    │   ├── gmail.rs
    │   └── onenote.rs
    └── routes/
        ├── me.rs
        └── connections.rs
```

**Dependencies to add:** `sqlx` (postgres, runtime-tokio, tls-rustls,
migrate, uuid, time), `reqwest` (rustls, json), `oauth2` (authorize URLs, PKCE,
code exchange, refresh), `jsonwebtoken` (ID tokens), `aes-gcm`, `sha2`,
`base64`, `rand`, `uuid`, `time`, `url`, `dotenvy` (development only), and
`tower_governor` (rate limits on `/v1/auth/*`).

**Extension points:**

```rust
/// One OAuth/OIDC provider. Adding Apple-on-server, GitHub, Slack… = one impl.
pub trait OAuthProvider: Send + Sync {
    fn id(&self) -> ProviderId;
    fn authorize_url(&self, params: &AuthorizeParams) -> Url;
    async fn exchange_code(&self, code: &str, verifier: &PkceVerifier) -> Result<TokenSet>;
    async fn refresh(&self, refresh_token: &SecretString) -> Result<TokenSet>;
    async fn verify_id_token(&self, id_token: &str, nonce: &str) -> Result<IdClaims>;
    async fn revoke(&self, token: &SecretString) -> Result<()>;
}

/// One integration. Adding Calendar, Drive, Outlook, OneDrive… = one entry.
pub struct Connector {
    pub id: &'static str,               // "gmail"
    pub provider: ProviderId,           // Google
    pub display_name: &'static str,     // "Gmail"
    pub scopes: &'static [&'static str],
    pub data_access: DataAccess,        // ClientDirect (D2a) | ServerSide (later)
}
```

**Database (Postgres):**

```sql
users          (id uuid pk, display_name, primary_email, created_at, deleted_at)
identities     (id uuid pk, user_id fk, provider, subject, tenant_id, email,
                created_at, UNIQUE (provider, tenant_id, subject))
connections    (id uuid pk, user_id fk, connector, provider, provider_subject,
                email, scopes text[], refresh_token_enc bytea, key_id,
                status, created_at, updated_at,
                UNIQUE (user_id, connector, provider_subject))
sessions       (id uuid pk, user_id fk, refresh_hash bytea, access_hash bytea,
                access_expires_at, refresh_expires_at, device_name,
                created_at, last_used_at, revoked_at)
auth_requests  (id uuid pk, state_hash, provider, intent, user_id null,
                connector null, provider_verifier_enc, nonce, app_challenge,
                expires_at, consumed_at)
grants         (code_hash pk, auth_request_id fk, user_id, connection_id null,
                expires_at, consumed_at)
```

**`curio-server/.env.example`:**

```dotenv
CURIO_SERVER_ADDR=127.0.0.1:8080
CURIO_PUBLIC_URL=http://localhost:8080          # https://api.<yourdomain> in prod (S1)
DATABASE_URL=postgres://curio:curio@localhost:5432/curio   # S3
CURIO_TOKEN_KEY=REPLACE_ME_base64_32_bytes      # S4: openssl rand -base64 32
CURIO_APP_REDIRECT=curio-auth://callback

GOOGLE_CLIENT_ID=REPLACE_ME.apps.googleusercontent.com    # G3
GOOGLE_CLIENT_SECRET=REPLACE_ME                           # G3

MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000  # M1
MICROSOFT_CLIENT_SECRET=REPLACE_ME                        # M4
MICROSOFT_TENANT=common                                   # M2

RUST_LOG=info,tower_http=debug
```

A provider whose client ID is still `REPLACE_ME` is left out at startup with a
warning, and `GET /v1/providers` reports it as disabled. The app hides that
provider's button.

### App

```
browser/crates/
├── curio-core        + Profile, ProfileId
├── curio-storage     + profiles table, profile_id columns, migration
├── curio-account     NEW: server client (ureq + curio-api), per-profile session
│                     storage (Keychain), ASWebAuthenticationSession bridge,
│                     Sign in with Apple bridge (objc2-authentication-services)
├── curio-connectors  NEW: Gmail + OneNote readers, context sources for curio-ai
├── curio-browser     + data store per profile
└── curio-ui          + welcome screen, profile switcher, Settings → Profiles /
                        Account / Integrations
```

**`browser/crates/curio-account/src/config.rs`:**

```rust
pub const SERVER_URL: &str = match option_env!("CURIO_SERVER_URL") {
    Some(url) => url,
    None => "http://localhost:8080", // S1: https://api.<yourdomain> for release builds
};
pub const AUTH_CALLBACK_SCHEME: &str = "curio-auth";
pub const APPLE_TEAM_ID: &str = match option_env!("CURIO_APPLE_TEAM_ID") {
    Some(id) => id,
    None => "REPLACE_ME", // A2
};
```

**Signing (`browser/script/bundle-macos.sh`):**
- `CURIO_PROVISIONING_PROFILE` (A5) → `Curio.app/Contents/embedded.provisionprofile`
- `browser/script/Curio.entitlements`: `com.apple.developer.applesignin = [Default]`,
  `com.apple.developer.team-identifier`, `com.apple.application-identifier`
- These are applied only when `CURIO_SIGN_IDENTITY` and the profile are set. The
  ad-hoc build keeps working, without Apple sign-in.
- `LSMinimumSystemVersion` → `14.0` (D1).
- A new `browser/script/dev-bundle.sh` builds a fast debug `.app` signed with
  your Apple Development identity, for testing Apple sign-in.

---

## 9. Adding the next integration (recipe)

Example: **Google Calendar**.

1. **Provider console:** enable the Calendar API. Add the scope
   (`calendar.readonly`) to the consent screen.
2. **Server:** add a `Connector { id: "gcal", provider: Google, scopes: &[…],
   data_access: ClientDirect }` entry in `connectors/mod.rs`. No new routes
   are needed. Connect, list, disconnect and token minting are generic.
3. **API types:** add `"gcal"` to the `ConnectorId` enum in `curio-api`.
4. **App:** add `curio-connectors/src/gcal.rs` with the reader and its context
   source. Register it so Settings → Integrations shows it.
5. **Tests:** a reader test against recorded JSON fixtures.

A new **provider** (for example Slack or GitHub) also needs an
`OAuthProvider` impl and its client ID and secret in `.env`.

---

## 10. Phases

| Phase | What | Needs from you |
|-------|------|----------------|
| **0** | Provider and hosting setup (section 1). Decide D1–D6 | G1–G6, M1–M5, A1–A5, S3–S4 |
| **1** | **Local profiles:** migration, data store per profile, switcher, Settings → Profiles, welcome screen with "Continue without an account" | D1 only |
| **2** | **Apple local identity:** spike AuthenticationServices from Rust, signing pipeline, dev bundle, Apple button | A1–A5 |
| **3** | **Server foundation:** `curio-api` crate, config, Postgres + sqlx migrations, error type, crypto, sessions, `CurrentUser` extractor, rate limits, `.env.example`, `docker compose` for local Postgres | S3, S4 (local values are fine) |
| **4** | **Server sign-in:** OAuthProvider for Google and Microsoft, auth requests and grants, `/v1/auth/*`, `/v1/me`, account linking, account deletion | G3, G4, M1–M4 (localhost redirects) |
| **5** | **App accounts:** `curio-account` crate, ASWebAuthenticationSession bridge, Google and Microsoft buttons on the welcome screen and New Profile, Settings → Account, sign-out, offline behaviour | — |
| **6** | **Integrations framework:** connections, connect flow, token minting, `needs_reauth` handling, Settings → Integrations | — |
| **7** | **Gmail connector:** list, search and read messages; MIME → text; "Mail" context source for the assistant | G5, G6 |
| **8** | **OneNote connector:** notebooks, sections and pages; HTML → text; "Notes" context source | M5 |
| **9** | **Ship:** Dockerfile, deploy, production redirect URIs, `CURIO_SERVER_URL` for release builds, Google verification + CASA, Microsoft publisher verification, CI release signing | S1, S2, S5, G7, M6 |

Phases 1 and 2 don't depend on the server, and phase 3 doesn't depend on the
app, so they can run in parallel.

---

## 11. Testing

**Server**
- Unit tests: PKCE, state and grant expiry and single use, AES-GCM round trip
  and key IDs, session rotation and reuse detection, and ID-token checks
  against a locally generated RSA key (expired, wrong `aud`, wrong `iss`, wrong
  nonce, Microsoft `{tid}` issuer).
- Integration tests: `#[sqlx::test]` (a fresh database per test) plus
  `wiremock` standing in for the Google and Microsoft token, JWKS and revoke
  endpoints. The tests drive the full `start → callback → token` flow through
  the router with `tower::ServiceExt::oneshot`.
- CI: the existing `server` job gains a Postgres service container.

**App**
- The profile migration on a copy of a pre-profiles database: all rows end up
  in "Default".
- The profile data-store ID stays stable across restarts. Deleting a profile
  removes its store.
- `curio-account` against a mock server. Gmail and OneNote readers against
  recorded fixtures.

**Manual checklist**
- [ ] Two profiles signed in to different Google accounts in the web
      content. Cookies don't leak between them.
- [ ] First run: each of the four welcome options creates a working profile.
- [ ] Google sign-in → account created. A second Mac with the same Google
      account → same account.
- [ ] Add Microsoft to a Google-created account → either one signs in to it.
- [ ] Connect Gmail from an Apple-only profile → the account and the connection
      are created in one step.
- [ ] Revoke Curio in the Google account's security page → the connection
      shows *Reconnect*.
- [ ] Offline launch → profiles and browsing work, and server features say
      "Offline".
- [ ] Delete account → provider access revoked, server rows gone, profile
      returns to local.
- [ ] Curio as the default browser → sign-in still appears in the system
      sheet, not in a tab.

---

## 12. Risks

| ID | Risk | Mitigation |
|----|------|------------|
| R1 | **Gmail's `gmail.readonly` is a restricted scope.** Before public launch Google requires app verification and, for apps whose servers hold restricted-scope tokens or data, a yearly third-party security assessment (CASA). It takes weeks and can cost money. Until then only test users (G6) can connect Gmail, and in Testing mode their refresh tokens expire after 7 days | Build and dogfood with test users. Start verification early. Choose D2 (a) and ask Google how it affects the assessment. Consider `gmail.metadata` if subjects and senders are enough for a first version (it's also restricted, but smaller) |
| R2 | Profiles on macOS 13 would silently share cookies | D1: require macOS 14 |
| R3 | `ASWebAuthenticationSession` might behave differently in an unbundled `cargo run` binary | Spike in phase 2. The fallback is to open the system browser and use a localhost loopback listener in the app for the final `curio-auth` hop |
| R4 | The Microsoft client secret expires (24 months at most) | Put the expiry in your calendar. Later, switch to a certificate credential |
| R5 | Microsoft work tenants can block user consent for `Notes.Read` | Show the admin-consent message Microsoft returns, and link to the admin-consent URL |
| R6 | A database leak exposes provider refresh tokens | AES-256-GCM with the key outside the database, key IDs for rotation, session tokens stored only as hashes |
| R7 | Apple only returns the name and email once | Save them before anything else can fail |
| R8 | The custom URL scheme can be intercepted | App ↔ server PKCE. Grants expire in 60 seconds and work once |
