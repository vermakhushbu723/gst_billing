import { Router } from 'express';
import { Product } from '../models/Product.js';
import { HttpError } from '../middleware/auth.js';

const router = Router();
const FIELDS = ['name', 'description', 'hsn', 'unit', 'rate', 'gstRate', 'active'];

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = { active: true };
  if (q) filter.name = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  res.json(await Product.find(filter).sort({ name: 1 }).lean());
});

router.post('/', async (req, res) => {
  const p = new Product();
  for (const f of FIELDS) if (req.body?.[f] !== undefined) p[f] = req.body[f];
  await p.save();
  res.status(201).json(p);
});

router.put('/:id', async (req, res) => {
  const p = await Product.findById(req.params.id);
  if (!p) throw new HttpError(404, 'Product not found');
  for (const f of FIELDS) if (req.body?.[f] !== undefined) p[f] = req.body[f];
  await p.save();
  res.json(p);
});

router.delete('/:id', async (req, res) => {
  // Invoices keep a copy of the item, so a soft delete is always safe.
  await Product.findByIdAndUpdate(req.params.id, { active: false });
  res.json({ ok: true });
});

export default router;
