import { Router } from 'express';
import { Company } from '../models/Company.js';
import { Invoice } from '../models/Invoice.js';
import { HttpError, requireAdmin } from '../middleware/auth.js';
import { stateName } from '../utils/states.js';

const router = Router();

const FIELDS = [
  'name', 'tagline', 'address', 'city', 'stateCode', 'pincode', 'mobile', 'email', 'gstin', 'pan',
  'bank', 'terms', 'invoicePrefix', 'docPrefixes', 'nextInvoiceNo', 'dueDays', 'color', 'logo', 'signature', 'active',
];
const MAX_IMAGE = 1_500_000; // ~1.1 MB binary as data URL

function apply(company, body) {
  for (const f of FIELDS) if (body[f] !== undefined) company[f] = body[f];
  if (Array.isArray(body.terms)) company.terms = body.terms.map((t) => String(t).trim()).filter(Boolean);
  company.state = stateName(company.stateCode) || company.state;
  for (const img of ['logo', 'signature']) {
    const v = company[img] || '';
    if (v && (!v.startsWith('data:image/') || v.length > MAX_IMAGE)) throw new HttpError(400, `${img} must be an image under 1 MB`);
  }
}

router.get('/', async (req, res) => {
  const filter = req.query.all === '1' ? {} : { active: true };
  const list = await Company.find(filter).sort({ createdAt: 1 }).lean();
  res.json(list);
});

router.get('/:id', async (req, res) => {
  const c = await Company.findById(req.params.id).select('+logo +signature').lean();
  if (!c) throw new HttpError(404, 'Company not found');
  res.json(c);
});

router.post('/', requireAdmin, async (req, res) => {
  const c = new Company();
  apply(c, req.body || {});
  await c.save();
  res.status(201).json(c);
});

router.put('/:id', requireAdmin, async (req, res) => {
  const c = await Company.findById(req.params.id).select('+logo +signature');
  if (!c) throw new HttpError(404, 'Company not found');
  apply(c, req.body || {});
  await c.save();
  res.json(c);
});

router.delete('/:id', requireAdmin, async (req, res) => {
  const used = await Invoice.exists({ company: req.params.id });
  if (used) {
    await Company.findByIdAndUpdate(req.params.id, { active: false });
    return res.json({ ok: true, deactivated: true, message: 'Company has invoices, so it was deactivated instead of deleted' });
  }
  await Company.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
