# AMARSHIHQ — Vijay's Dev HQ

> **Command layer:** Claude Code runs on the DigitalOcean Droplet via SSH and drives everything — builds, deploys, config changes — without touching a dashboard or spinning up CI/CD.

---

## Architecture overview

```
Claude Code  (SSH into Droplet)
   │
   ├── /apps/anelia   → Express API  → port 3001 (loopback only)
   ├── /apps/school   → Express API  → port 3002 (loopback only)
   │
   ├── Frontends built on Droplet → netlify deploy --prod --dir=dist
   │   (no GitHub push, no CI pipeline)
   │
   ├── Cloudflare Tunnel (cloudflared daemon)
   │      api-anelia.yourdomain.com  → localhost:3001
   │      api-school.yourdomain.com  → localhost:3002
   │      (zero open inbound ports, free TLS, IP hidden)
   │
   ├── Data  → Airtable REST API (separate base per app)
   │
   └── Files → Cloudflare R2 (S3-compatible endpoint)
```

### Cloudflare DNS routing

| Subdomain | Target |
|---|---|
| `anelia.yourdomain.com` | CNAME → Netlify (frontend) |
| `api-anelia.yourdomain.com` | Cloudflare Tunnel → Droplet :3001 |
| `school.yourdomain.com` | CNAME → Netlify (frontend) |
| `api-school.yourdomain.com` | Cloudflare Tunnel → Droplet :3002 |
| `dashboard.yourdomain.com` | CNAME → Netlify (shared dashboard) |

---

## Repo layout

```
AMARSHIHQ/
├── apps/
│   ├── anelia/          Express API skeleton (port 3001)
│   │   ├── index.js
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .env.example
│   └── school/          Express API skeleton (port 3002)
│       ├── index.js
│       ├── package.json
│       ├── Dockerfile
│       └── .env.example
├── cloudflared/
│   └── config.yml       Tunnel config (fill in tunnel ID)
├── dashboard/
│   ├── index.html       Shareable stack overview page
│   └── netlify.toml     Netlify deploy config for dashboard subdomain
├── scripts/
│   └── deploy.sh        Netlify CLI direct deploy (anelia|school|dashboard|all)
├── docker-compose.yml   Manages both app containers
└── .gitignore
```

---

## Quick-start (Droplet bootstrap)

### 1. Provision the Droplet

```bash
# DigitalOcean Basic — 2 GB / 1 vCPU / $12/mo
# Choose Ubuntu 24.04 LTS, NYC or SFO region
# OR use doctl:
doctl compute droplet create vijay-hq \
  --size s-1vcpu-2gb \
  --image ubuntu-24-04-x64 \
  --region nyc3 \
  --ssh-keys <your-key-id>
```

### 2. SSH in and install dependencies

```bash
ssh root@your_droplet_ip

# Docker
curl -fsSL https://get.docker.com | sh
# Claude Code
npm install -g @anthropic-ai/claude-code
# Netlify CLI
npm install -g netlify-cli
# Cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
```

### 3. Clone this repo onto the Droplet

```bash
git clone https://github.com/ACoolNerd/AMARSHIHQ.git /root/hq
cd /root/hq
```

### 4. Configure environment files

```bash
cp apps/anelia/.env.example apps/anelia/.env
cp apps/school/.env.example apps/school/.env
# Edit both .env files with real Airtable keys, R2 credentials, etc.
nano apps/anelia/.env
nano apps/school/.env
```

### 5. Start the apps

```bash
docker compose up -d --build
docker compose ps      # both containers should show "running"
```

### 6. Set up Cloudflare Tunnel

```bash
cloudflared tunnel login                    # opens browser auth
cloudflared tunnel create vijay-droplet     # note the tunnel ID printed
# Edit cloudflared/config.yml — replace <YOUR_TUNNEL_ID>
nano cloudflared/config.yml
cloudflared tunnel route dns vijay-droplet api-anelia.yourdomain.com
cloudflared tunnel route dns vijay-droplet api-school.yourdomain.com
cloudflared service install
systemctl start cloudflared
```

### 7. Deploy frontends to Netlify

```bash
netlify login                               # or set NETLIFY_AUTH_TOKEN
chmod +x scripts/deploy.sh
./scripts/deploy.sh all                     # deploys anelia, school, and dashboard
```

---

## Dashboard (shared reference page)

A pre-built, shareable status and architecture page lives at `dashboard/index.html`. Deploy it to its own Netlify site and point `dashboard.yourdomain.com` at it — share the URL with anyone who needs to understand the stack.

```bash
# Deploy just the dashboard
./scripts/deploy.sh dashboard

# Or set a specific Netlify site ID for the dashboard
export NETLIFY_SITE_ID_DASHBOARD=your-dashboard-site-id
./scripts/deploy.sh dashboard
```

The dashboard covers: what every service is, where every URL lives, what can be built next, and a side-by-side comparison of alternative deployment options.

---

## Alternative development environments

### Option A — Local dev (no Docker, fastest iteration)

Run both apps directly on your machine before spinning up the Droplet:

```bash
# Terminal 1
cd apps/anelia && cp .env.example .env && npm install && npm run dev

# Terminal 2
cd apps/school && cp .env.example .env && npm install && npm run dev

# Test both health endpoints
curl http://localhost:3001/health
curl http://localhost:3002/health
```

### Option B — pm2 (lightweight process manager, no Docker)

Good if Docker feels heavy on a 2 GB box:

```bash
npm install -g pm2
pm2 start apps/anelia/index.js --name anelia
pm2 start apps/school/index.js  --name school
pm2 save && pm2 startup          # survive reboots
pm2 logs anelia                  # tail logs
pm2 restart school               # rolling restart
```

### Option C — Docker Compose (current default, recommended for the Droplet)

Fully isolated containers, automatic restart on crash, easy to update individually:

```bash
docker compose up -d --build          # start / rebuild both
docker compose restart anelia         # restart one container
docker compose logs -f school         # stream logs
docker compose exec anelia sh         # shell into container
```

---

## Alternative deployment options

The table below compares the current stack to common alternatives so you can make an informed switch if your needs grow.

| Option | Dev workflow | Deploy | Approx. cost | Best for |
|---|---|---|---|---|
| **Current ✅** DO + Netlify + CF Tunnel | SSH → Claude Code | `./scripts/deploy.sh` | ~$12/mo | Solo, no CI overhead |
| GitHub Actions CI/CD | Push to main | Auto on merge | ~$12/mo (same DO) | Teams, audit trails, rollbacks |
| Railway.app | Connect GitHub repo | Git push | ~$5–15/mo | Fastest start, zero server management |
| Render.com | Connect GitHub + Docker | Git push | Free → $7/mo per svc | Simple APIs (sleeps on free tier) |
| Fly.io | `fly deploy` from CLI | CLI push | ~$3–6/mo per app | Global edge, more control than Railway |
| Hetzner VPS | Same as current | `./scripts/deploy.sh` | ~€4–5/mo | Lowest raw price, EU latency |

> **Why DigitalOcean over Hetzner for this setup?** DO's `doctl` CLI integrates cleanly with Claude Code for provisioning and snapshots. Hetzner's abuse-detection is slower to recover from when you're solo and need the box back fast. The ~$8/mo premium is worth it at this scale.

---

## Claude Code prompt pack

Paste these prompts directly into Claude Code once SSH'd into the Droplet.

### Bootstrap the full stack

```
I am building a 2-app infrastructure on this DigitalOcean Droplet.
Apps: "anelia" on port 3001 and "school" on port 3002.
Backend: Node.js/Express in /root/hq/apps/{anelia,school}.
Frontends deploy via `netlify deploy --prod --dir=dist` (no GitHub).
Backend is exposed only through Cloudflare Tunnel (cloudflared).
Data layer: Airtable REST API. File storage: Cloudflare R2 (S3-compatible).
Please verify docker compose is running, cloudflared is active,
and both /health endpoints return 200. Fix anything that is broken.
```

### Add a new API route (Anelia)

```
In /root/hq/apps/anelia/index.js, add a POST /api/items route that:
1. Accepts JSON body { name, description }.
2. Writes a new record to Airtable base $AIRTABLE_BASE_ID using the REST API.
3. Returns the created record as JSON with status 201.
Use fetch (Node 18+). Read credentials from process.env. Restart the container after.
```

### Deploy after a code change

```
I just updated /root/hq/apps/anelia/index.js.
Please: rebuild the Docker container (`docker compose up -d --build anelia`),
confirm /health returns 200, then run `./scripts/deploy.sh anelia`
to push the updated frontend to Netlify.
```

### Check Airtable record headroom

```
Query the Airtable base for app "school" (base ID: $AIRTABLE_BASE_ID)
and count total records across all tables. Print the count and warn me
if we are above 800 records (free tier cap is 1,000).
```

### Rotate R2 credentials

```
Update R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY in both
/root/hq/apps/anelia/.env and /root/hq/apps/school/.env
with the new values I paste below. Then restart both containers
and confirm /health is still 200 for each.
```

---

## One-time Cloudflare DNS setup (manual, ~5 min)

In the Cloudflare dashboard for `yourdomain.com`:

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `anelia` | `your-netlify-site.netlify.app` | ✅ Proxied |
| CNAME | `school` | `your-school-netlify-site.netlify.app` | ✅ Proxied |
| CNAME | `api-anelia` | `<tunnel-id>.cfargotunnel.com` | ✅ Proxied |
| CNAME | `api-school` | `<tunnel-id>.cfargotunnel.com` | ✅ Proxied |
| CNAME | `dashboard` | `your-dashboard.netlify.app` | ✅ Proxied |

---

## Cost snapshot

| Service | Tier | Cost |
|---|---|---|
| DigitalOcean Droplet | Basic 2GB/1vCPU | ~$12/mo |
| Cloudflare Tunnel | Free | $0 |
| Cloudflare R2 | Free (10 GB) | $0 |
| Netlify | Starter | $0 |
| Airtable | Free (until 2028) | $0 |
| **Total** | | **~$12/mo** |

---

## ⚠️ Airtable record cap reminder

Airtable free tier = **1,000 records/base**. The school app's `/api/submissions` endpoint writes one record per submission. Run the "Check Airtable record headroom" Claude Code prompt every 6 months.

---

## License

MIT © ACoolNERD