'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(express.json());

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', app: 'anelia', ts: new Date().toISOString() });
});

// ── Airtable proxy example ────────────────────────────────────────────────────
// Replace with real Airtable REST calls once your base is set up.
app.get('/api/records', async (_req, res) => {
  try {
    // TODO: call Airtable REST API using process.env.AIRTABLE_API_KEY + AIRTABLE_BASE_ID
    res.json({ records: [], message: 'Airtable integration — configure .env' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Cloudflare R2 / S3-compatible example ─────────────────────────────────────
app.get('/api/files', async (_req, res) => {
  try {
    // TODO: list objects from R2 bucket using S3-compatible client
    // endpoint: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
    res.json({ files: [], message: 'R2 integration — configure .env' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[anelia] listening on port ${PORT}`);
});
