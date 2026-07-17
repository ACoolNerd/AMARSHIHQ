# AMARSHIHQ — Vijay's Dev HQ

> **Command layer:** Claude Code runs on the DigitalOcean Droplet via SSH and drives everything — builds, deploys, config changes — without touching a dashboard or spinning up CI/CD.

---

## Table of contents

1. [What this is](#what-this-is)
2. [Architecture](#architecture)
3. [Repo layout](#repo-layout)
4. [Required secrets](#required-secrets)
5. [Launch checklist](#launch-checklist)
6. [Local development](#local-development)
7. [Deploy workflow](#deploy-workflow)
8. [Operate](#operate)
9. [Rollback](#rollback)
10. [Troubleshoot](#troubleshoot)
11. [Extend](#extend)
12. [Alternative deployment options](#alternative-deployment-options)
13. [Claude Code prompt pack](#claude-code-prompt-pack)
14. [Cost snapshot](#cost-snapshot)

---

## What this is

AMARSHIHQ is a two-app solo developer infrastructure running on a single DigitalOcean Droplet. It hosts:

- **anelia** — Express API on port 3001 (loopback only, proxied via Cloudflare Tunnel)
- **school** — Express API on port 3002 (same pattern)

Frontends are built locally and deployed directly to Netlify with `netlify deploy`. There is no push-to-deploy pipeline — Claude Code is the CI/CD layer.

GitHub Actions runs validation only (install + compose check) on every push. No secrets leave GitHub.

---

## Architecture

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
├── .github/
│   └── workflows/
│       └── ci.yml            Validate apps + Compose syntax (no deploy)
├── apps/
│   ├── anelia/               Express API (port 3001)
│   │   ├── index.js
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .env.example
│   └── school/               Express API (port 3002)
│       ├── index.js
│       ├── package.json
│       ├── Dockerfile
│       └── .env.example
├── cloudflared/
│   └── config.yml            Tunnel config (fill in tunnel ID)
├── dashboard/
│   ├── index.html            Shareable stack overview page
│   └── netlify.toml          Netlify deploy config for dashboard subdomain
├── scripts/
│   ├── deploy.sh             Netlify CLI direct deploy (anelia|school|dashboard|all)
│   ├── health-check.sh       Verify all services are up on the Droplet
│   └── rollback.sh           Revert a container to its previous image
├── docker-compose.yml        Manages both app containers
└── .gitignore
```

---

## Required secrets

These live in `.env` files on the Droplet — never commit them.

| Variable | Used by | Where to get it |
|---|---|---|
| `PORT` | anelia (3001), school (3002) | Set in `.env.example` |
| `AIRTABLE_API_KEY` | both apps | Airtable → Account → API |
| `AIRTABLE_BASE_ID` | both apps | Airtable → API docs for your base |
| `R2_ACCOUNT_ID` | both apps | Cloudflare dashboard → R2 |
| `R2_ACCESS_KEY_ID` | both apps | Cloudflare R2 → Manage API tokens |
| `R2_SECRET_ACCESS_KEY` | both apps | Same as above |
| `R2_BUCKET_NAME` | both apps | Your R2 bucket name |
| `R2_ENDPOINT` | both apps | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |

Template files: `apps/anelia/.env.example`, `apps/school/.env.example`

---

## Launch checklist

Complete these steps once, in order, to go from zero to production.

### Step 1 — Provision the Droplet

```bash
# DigitalOcean Basic — 2 GB / 1 vCPU / Ubuntu 24.04 LTS (~$12/mo)
doctl compute droplet create vijay-hq \
  --size s-1vcpu-2gb \
  --image ubuntu-24-04-x64 \
  --region nyc3 \
  --ssh-keys <your-key-id>
```

### Step 2 — Install dependencies on the Droplet

```bash
ssh root@your_droplet_ip

# Docker
curl -fsSL https://get.docker.com | sh

# Node tooling
npm install -g @anthropic-ai/claude-code netlify-cli

# Cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
```

### Step 3 — Clone the repo

```bash
git clone https://github.com/ACoolNerd/AMARSHIHQ.git /root/hq
cd /root/hq
```

### Step 4 — Configure environment files

```bash
cp apps/anelia/.env.example apps/anelia/.env
cp apps/school/.env.example apps/school/.env
nano apps/anelia/.env   # fill in Airtable + R2 credentials
nano apps/school/.env
```

### Step 5 — Start the containers

```bash
docker compose up -d --build
docker compose ps      # both containers should show "running"
```

### Step 6 — Set up Cloudflare Tunnel

```bash
cloudflared tunnel login                        # browser auth
cloudflared tunnel create vijay-droplet         # note the tunnel ID
nano cloudflared/config.yml                     # replace <YOUR_TUNNEL_ID>
cloudflared tunnel route dns vijay-droplet api-anelia.yourdomain.com
cloudflared tunnel route dns vijay-droplet api-school.yourdomain.com
cloudflared service install
systemctl start cloudflared
```

### Step 7 — Configure Cloudflare DNS (manual, ~5 min)

In the Cloudflare dashboard for `yourdomain.com`:

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `anelia` | `your-netlify-site.netlify.app` | ✅ Proxied |
| CNAME | `school` | `your-school-netlify-site.netlify.app` | ✅ Proxied |
| CNAME | `api-anelia` | `<tunnel-id>.cfargotunnel.com` | ✅ Proxied |
| CNAME | `api-school` | `<tunnel-id>.cfargotunnel.com` | ✅ Proxied |
| CNAME | `dashboard` | `your-dashboard.netlify.app` | ✅ Proxied |

### Step 8 — Deploy frontends to Netlify

```bash
netlify login                   # or export NETLIFY_AUTH_TOKEN=...
chmod +x scripts/deploy.sh scripts/health-check.sh scripts/rollback.sh
./scripts/deploy.sh all         # deploys anelia, school, and dashboard
```

### Step 9 — Verify launch readiness

```bash
./scripts/health-check.sh       # all checks should pass
curl https://api-anelia.yourdomain.com/health
curl https://api-school.yourdomain.com/health
```

**Launch gates — all must be ✅ before going live:**

- [ ] Both containers running (`docker compose ps`)
- [ ] `localhost:3001/health` → `{"status":"ok","app":"anelia",...}`
- [ ] `localhost:3002/health` → `{"status":"ok","app":"school",...}`
- [ ] `cloudflared` service active (`systemctl is-active cloudflared`)
- [ ] `api-anelia.yourdomain.com/health` → 200
- [ ] `api-school.yourdomain.com/health` → 200
- [ ] `anelia.yourdomain.com` loads frontend
- [ ] `school.yourdomain.com` loads frontend
- [ ] `dashboard.yourdomain.com` loads dashboard
- [ ] `.env` files present and not committed to git

---

## Local development

Run both apps directly on your machine — no Docker required.

```bash
# Terminal 1
cd apps/anelia && cp .env.example .env && npm install && npm run dev

# Terminal 2
cd apps/school && cp .env.example .env && npm install && npm run dev

# Verify both are up
curl http://localhost:3001/health
curl http://localhost:3002/health
```

Alternatively, use **pm2** (lightweight, no Docker):

```bash
npm install -g pm2
pm2 start apps/anelia/index.js --name anelia
pm2 start apps/school/index.js --name school
pm2 save && pm2 startup          # survive reboots
pm2 logs anelia                  # tail logs
pm2 restart school               # rolling restart
```

---

## Deploy workflow

All deploys run from the Droplet via SSH. There is no push-to-deploy.

### Update an API (backend change)

```bash
# 1. Edit the source file
nano /root/hq/apps/anelia/index.js

# 2. Save a rollback point
docker tag anelia:latest anelia:previous

# 3. Rebuild and restart
docker compose up -d --build anelia

# 4. Verify
curl http://localhost:3001/health
```

### Update a frontend

```bash
# Build the frontend (in the app's front-end dir)
npm run build

# Deploy to Netlify
./scripts/deploy.sh anelia
```

### Deploy all

```bash
./scripts/deploy.sh all
```

### Deploy only the dashboard

```bash
./scripts/deploy.sh dashboard
# Or with an explicit Netlify site ID:
export NETLIFY_SITE_ID_DASHBOARD=your-site-id
./scripts/deploy.sh dashboard
```

---

## Operate

### Daily commands

```bash
docker compose ps                        # container status
docker compose logs -f anelia            # stream anelia logs
docker compose logs -f school            # stream school logs
./scripts/health-check.sh               # full stack health check
```

### Restart a single container

```bash
docker compose restart anelia
docker compose restart school
```

### Rebuild a single container (after code change)

```bash
docker compose up -d --build anelia
docker compose up -d --build school
```

### Shell into a container

```bash
docker compose exec anelia sh
docker compose exec school sh
```

### Rotate credentials

```bash
nano apps/anelia/.env   # update keys
nano apps/school/.env
docker compose restart  # pick up new env vars
```

### Monitor Cloudflare Tunnel

```bash
systemctl status cloudflared
journalctl -u cloudflared -f    # live tunnel logs
```

---

## Rollback

Before any deploy, save a rollback point:

```bash
docker tag anelia:latest anelia:previous
docker tag school:latest school:previous
```

To revert:

```bash
./scripts/rollback.sh anelia
./scripts/rollback.sh school
```

The rollback script:
1. Tags the current (broken) image as `<app>:broken` for inspection.
2. Promotes `<app>:previous` → `<app>:latest`.
3. Restarts the container.
4. Verifies `/health` returns 200.

---

## Troubleshoot

### Container won't start

```bash
docker compose logs --tail=50 anelia     # check error output
docker compose up anelia                 # run in foreground for full output
```

### `/health` returns an error

```bash
# Check the container is actually running
docker compose ps

# Check the port binding
docker compose port anelia 3001

# Hit it directly
curl -v http://localhost:3001/health
```

### Cloudflare Tunnel is down

```bash
systemctl status cloudflared
journalctl -u cloudflared --since "10 min ago"
systemctl restart cloudflared
```

### Environment variable missing

```bash
docker compose exec anelia printenv | grep AIRTABLE
# If blank, edit apps/anelia/.env and restart:
docker compose restart anelia
```

### Airtable record cap warning

Airtable free tier = **1,000 records/base**. The school `/api/submissions` endpoint writes one record per submission. Check headroom every 6 months:

```
Query the Airtable base for app "school" (base ID: $AIRTABLE_BASE_ID)
and count total records across all tables. Print the count and warn me
if we are above 800 records (free tier cap is 1,000).
```

---

## Extend

### Add a new API route

Use this Claude Code prompt on the Droplet:

```
In /root/hq/apps/anelia/index.js, add a POST /api/items route that:
1. Accepts JSON body { name, description }.
2. Writes a new record to Airtable base $AIRTABLE_BASE_ID using the REST API.
3. Returns the created record as JSON with status 201.
Use fetch (Node 18+). Read credentials from process.env. Restart the container after.
```

### Bootstrap the full stack from scratch

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

### Rotate R2 credentials

```
Update R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY in both
/root/hq/apps/anelia/.env and /root/hq/apps/school/.env
with the new values I paste below. Then restart both containers
and confirm /health is still 200 for each.
```

### Add a third app

1. Copy `apps/anelia/` → `apps/newapp/`, update `PORT` to 3003.
2. Add a `newapp` service in `docker-compose.yml` bound to `127.0.0.1:3003:3003`.
3. Add a new ingress rule in `cloudflared/config.yml`.
4. Add DNS entries in Cloudflare.
5. Add a `deploy_app "newapp"` case in `scripts/deploy.sh`.

---

## Alternative deployment options

| Option | Dev workflow | Deploy | Approx. cost | Best for |
|---|---|---|---|---|
| **Current ✅** DO + Netlify + CF Tunnel | SSH → Claude Code | `./scripts/deploy.sh` | ~$12/mo | Solo, no CI overhead |
| GitHub Actions CI/CD | Push to main | Auto on merge | ~$12/mo (same DO) | Teams, audit trails |
| Railway.app | Connect GitHub repo | Git push | ~$5–15/mo | Fastest start, zero server management |
| Render.com | Connect GitHub + Docker | Git push | Free → $7/mo per svc | Simple APIs (sleeps on free tier) |
| Fly.io | `fly deploy` from CLI | CLI push | ~$3–6/mo per app | Global edge, more control than Railway |
| Hetzner VPS | Same as current | `./scripts/deploy.sh` | ~€4–5/mo | Lowest raw price, EU latency |

> **Why DigitalOcean over Hetzner?** DO's `doctl` CLI integrates cleanly with Claude Code for provisioning and snapshots. Hetzner's abuse-detection is slower to recover from when you're solo. The ~$8/mo premium is worth it at this scale.

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

## License

MIT © ACoolNERD