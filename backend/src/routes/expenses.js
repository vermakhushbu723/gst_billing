import { Router } from 'express';
import mongoose from 'mongoose';
import { Expense } from '../models/Expense.js';
import { Company } from '../models/Company.js';
import { HttpError, assertOwn } from '../middleware/auth.js';
import { round2 } from '../utils/gst.js';
import { money, notify } from '../utils/notify.js';

const router = Router();
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function apply(doc, b) {
  if (b.company !== undefined) doc.company = b.company;
  if (b.date !== undefined) doc.date = b.date;
  if (b.category !== undefined) doc.category = String(b.category).trim();
  if (b.amount !== undefined) doc.amount = round2(Number(b.amount) || 0);
  for (const f of ['mode', 'paidTo', 'note']) if (b[f] !== undefined) doc[f] = String(b[f]).trim();
}

async function validate(doc) {
  if (!mongoose.isValidObjectId(doc.company) || !(await Company.exists({ _id: doc.company }))) throw new HttpError(400, 'Select a company');
  if (!DATE_RE.test(doc.date || '')) throw new HttpError(400, 'Date is required');
  if (!doc.category) throw new HttpError(400, 'Select a category');
  if (!(doc.amount > 0)) throw new HttpError(400, 'Amount must be more than 0');
}

router.get('/', async (req, res) => {
  const { company, from, to, category } = req.query;
  const filter = {};
  if (company && company !== 'all') filter.company = company;
  if (category && category !== 'all') filter.category = category;
  if (from || to) {
    filter.date = {};
    if (from) filter.date.$gte = String(from);
    if (to) filter.date.$lte = String(to);
  }
  const items = await Expense.find(filter).sort({ date: -1, createdAt: -1 }).limit(2000).lean();
  const byCategory = {};
  for (const e of items) byCategory[e.category] = round2((byCategory[e.category] || 0) + e.amount);
  res.json({ items, total: round2(items.reduce((s, e) => s + e.amount, 0)), byCategory });
});

router.post('/', async (req, res) => {
  const e = new Expense({ createdBy: req.user._id });
  apply(e, req.body || {});
  await validate(e);
  await e.save();
  await notify({ type: 'expense', severity: 'info', actor: req.user._id, company: e.company, link: '/expenses',
    title: `Expense added ${money(e.amount)}`, body: `${e.category}${e.paidTo ? ' • ' + e.paidTo : ''} • by ${req.user.name}` });
  res.status(201).json(e);
});

router.put('/:id', async (req, res) => {
  const e = assertOwn(req, await Expense.findById(req.params.id));
  apply(e, req.body || {});
  await validate(e);
  await e.save();
  res.json(e);
});

router.delete('/:id', async (req, res) => {
  assertOwn(req, await Expense.findById(req.params.id).select('company').lean());
  await Expense.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
