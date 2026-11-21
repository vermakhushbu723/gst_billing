import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { Invoice } from '../models/Invoice.js';
import { config } from '../config.js';
import { STATES } from '../utils/states.js';

const router = Router();

router.get('/states', (_req, res) => res.json(STATES));

// Shared invoice PDF (link sent on WhatsApp). The token is random and unguessable.
router.get('/pdf/:file', async (req, res) => {
  const token = String(req.params.file).replace(/\.pdf$/i, '');
  if (!/^[a-f0-9]{36}$/.test(token)) return res.status(404).json({ message: 'Not found' });
  const file = path.resolve(config.uploadDir, 'pdf', `${token}.pdf`);
  if (!fs.existsSync(file)) return res.status(404).json({ message: 'Invoice PDF not found' });
  const inv = await Invoice.findOne({ shareToken: token }).select('invoiceNo invoicePrefix billTo.name').lean();
  if (!inv) return res.status(404).json({ message: 'Not found' });
  const party = String(inv.billTo?.name || 'Invoice').replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '');
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="${party}_Sales_Invoice_${inv.invoicePrefix || ''}${inv.invoiceNo}.pdf"`);
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(file).pipe(res);
});

export default router;
