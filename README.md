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
├── scripts/
│   └── deploy.sh        Netlify CLI direct deploy
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
./scripts/deploy.sh all
```

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