import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { Invoice } from '../models/Invoice.js';
import { Company } from '../models/Company.js';
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
  const inv = await Invoice.findOne({ shareToken: token }).select('docType gst invoiceNo invoicePrefix billTo.name').lean();
  if (!inv) return res.status(404).json({ message: 'Not found' });
  const party = String(inv.billTo?.name || 'Invoice').replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const word = inv.gst === false
    ? { quotation: 'Estimate', credit_note: 'Sales_Return', challan: 'Delivery_Challan' }[inv.docType] || 'Bill'
    : { quotation: 'Quotation', credit_note: 'Credit_Note', challan: 'Delivery_Challan' }[inv.docType] || 'Sales_Invoice';
  const no = `${inv.invoicePrefix || ''}${inv.invoiceNo}`.replace(/[^A-Za-z0-9-]+/g, '_');
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="${party}_${word}_${no}.pdf"`);
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(file).pipe(res);
});

// Public invoice page (/share/<token> in the web app): the document plus the
// company's logo and signature, so the browser can draw the same PDF. The token
// is random and unguessable; nothing else about the business is exposed.
router.get('/invoice/:token', async (req, res) => {
  const token = String(req.params.token);
  if (!/^[a-f0-9]{36}$/.test(token)) return res.status(404).json({ message: 'Not found' });
  const inv = await Invoice.findOne({ shareToken: token })
    .select('-createdBy -payments.note -shareToken')
    .lean();
  if (!inv) return res.status(404).json({ message: 'This invoice link is not valid' });
  const company = await Company.findById(inv.company).select('+logo +signature color name').lean();
  res.setHeader('Cache-Control', 'no-store');
  res.json({ invoice: inv, company: { _id: company?._id, name: company?.name, color: company?.color, logo: company?.logo || '', signature: company?.signature || '' } });
});

export default router;
