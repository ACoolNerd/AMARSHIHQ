'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 3002;

app.use(express.json());

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', app: 'school', ts: new Date().toISOString() });
});

// ── Airtable proxy example ────────────────────────────────────────────────────
app.get('/api/records', async (_req, res) => {
  try {
    // TODO: call Airtable REST API using process.env.AIRTABLE_API_KEY + AIRTABLE_BASE_ID
    res.json({ records: [], message: 'Airtable integration — configure .env' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Submissions / school-specific endpoint ────────────────────────────────────
app.post('/api/submissions', async (req, res) => {
  try {
    const payload = req.body;
    // TODO: write submission to Airtable base
    // Watch record volume — Airtable free tier caps at 1,000 records/base
    res.status(201).json({ received: true, payload });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[school] listening on port ${PORT}`);
});
