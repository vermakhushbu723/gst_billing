import { Router } from 'express';
import { Product } from '../models/Product.js';
import { HttpError, assertOwn } from '../middleware/auth.js';
import { Company } from '../models/Company.js';
import mongoose from 'mongoose';

const router = Router();
const FIELDS = ['name', 'description', 'hsn', 'unit', 'rate', 'gstRate', 'active'];

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = { active: true };
  const company = req.query.company;
  if (company && company !== 'all' && mongoose.isValidObjectId(company)) filter.company = company;
  if (q) filter.name = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  res.json(await Product.find(filter).sort({ name: 1 }).lean());
});

router.post('/', async (req, res) => {
  const p = new Product();
  const company = req.body?.company;
  if (!mongoose.isValidObjectId(company) || !(await Company.exists({ _id: company }))) throw new HttpError(400, 'Select the company for this product');
  p.company = company;
  for (const f of FIELDS) if (req.body?.[f] !== undefined) p[f] = req.body[f];
  await p.save();
  res.status(201).json(p);
});

router.put('/:id', async (req, res) => {
  const p = assertOwn(req, await Product.findById(req.params.id));
  for (const f of FIELDS) if (req.body?.[f] !== undefined) p[f] = req.body[f];
  await p.save();
  res.json(p);
});

router.delete('/:id', async (req, res) => {
  assertOwn(req, await Product.findById(req.params.id).select('company').lean());
  // Invoices keep a copy of the item, so a soft delete is always safe.
  await Product.findByIdAndUpdate(req.params.id, { active: false });
  res.json({ ok: true });
});

export default router;
