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
    console.error('[school] /api/records error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Submissions / school-specific endpoint ────────────────────────────────────
app.post('/api/submissions', async (req, res) => {
  try {
    const { name, description } = req.body || {};
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: '`name` is required and must be a non-empty string' });
    }
    const payload = { name: name.trim(), description: typeof description === 'string' ? description.trim() : '' };
    // TODO: write submission to Airtable base
    // Watch record volume — Airtable free tier caps at 1,000 records/base
    res.status(201).json({ received: true, payload });
  } catch (err) {
    console.error('[school] /api/submissions error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[school] listening on port ${PORT}`);
});
