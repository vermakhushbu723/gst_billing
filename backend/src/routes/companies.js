import { Router } from 'express';
import { Company } from '../models/Company.js';
import { Invoice } from '../models/Invoice.js';
import { HttpError, assertOwn, requireAdmin, requireSuperAdmin } from '../middleware/auth.js';
import { User } from '../models/User.js';
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
  if (req.scope) filter._id = req.scope; // company login sees only itself
  const list = await Company.find(filter).sort({ createdAt: 1 }).lean();
  // number of logins per company, for the main admin's Companies screen
  const counts = await User.aggregate([{ $match: { company: { $ne: null } } }, { $group: { _id: '$company', n: { $sum: 1 } } }]);
  const map = new Map(counts.map((c) => [String(c._id), c.n]));
  res.json(list.map((c) => ({ ...c, logins: map.get(String(c._id)) || 0 })));
});

router.get('/:id', async (req, res) => {
  const c = assertOwn(req, await Company.findById(req.params.id).select('+logo +signature').lean(), '_id');
  res.json(c);
});

router.post('/', requireSuperAdmin, async (req, res) => {
  const c = new Company();
  apply(c, req.body || {});
  await c.save();
  res.status(201).json(c);
});

router.put('/:id', requireAdmin, async (req, res) => {
  const c = assertOwn(req, await Company.findById(req.params.id).select('+logo +signature'), '_id');
  const body = { ...(req.body || {}) };
  delete body.company;
  if (req.scope) delete body.active; // a company cannot switch itself off
  apply(c, body);
  await c.save();
  res.json(c);
});

router.delete('/:id', requireSuperAdmin, async (req, res) => {
  const used = await Invoice.exists({ company: req.params.id });
  if (used) {
    await Company.findByIdAndUpdate(req.params.id, { active: false });
    return res.json({ ok: true, deactivated: true, message: 'Company has invoices, so it was deactivated instead of deleted' });
  }
  await Company.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
