import { Router } from 'express';
import { Customer } from '../models/Customer.js';
import { Invoice } from '../models/Invoice.js';
import { HttpError } from '../middleware/auth.js';
import { stateName } from '../utils/states.js';
import { round2 } from '../utils/gst.js';

const router = Router();
const FIELDS = ['name', 'phone', 'email', 'gstin', 'pan', 'billingAddress', 'shippingName', 'shippingAddress', 'sameAsBilling', 'stateCode', 'openingBalance', 'active'];

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function apply(doc, body) {
  for (const f of FIELDS) if (body[f] !== undefined) doc[f] = body[f];
  doc.state = stateName(doc.stateCode) || doc.state;
  if (!doc.pan && doc.gstin && doc.gstin.length >= 12) doc.pan = doc.gstin.slice(2, 12);
}

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = { active: true };
  if (q) filter.$or = [{ name: new RegExp(escapeRe(q), 'i') }, { phone: new RegExp(escapeRe(q), 'i') }, { gstin: new RegExp(escapeRe(q), 'i') }];
  const customers = await Customer.find(filter).sort({ name: 1 }).lean();
  // Outstanding balance per customer
  const dues = await Invoice.aggregate([
    { $match: { status: { $ne: 'cancelled' } } },
    { $group: { _id: '$customer', balance: { $sum: '$balance' }, sales: { $sum: '$total' } } },
  ]);
  const map = new Map(dues.map((d) => [String(d._id), d]));
  res.json(customers.map((c) => ({
    ...c,
    balance: round2((map.get(String(c._id))?.balance || 0) + (c.openingBalance || 0)),
    sales: round2(map.get(String(c._id))?.sales || 0),
  })));
});

router.get('/:id', async (req, res) => {
  const c = await Customer.findById(req.params.id).lean();
  if (!c) throw new HttpError(404, 'Customer not found');
  res.json(c);
});

router.get('/:id/statement', async (req, res) => {
  const c = await Customer.findById(req.params.id).lean();
  if (!c) throw new HttpError(404, 'Customer not found');
  const invoices = await Invoice.find({ customer: c._id })
    .select('invoiceNo invoicePrefix invoiceDate dueDate total receivedAmount balance status company companySnapshot.name')
    .sort({ invoiceDate: -1, invoiceNo: -1 })
    .lean();
  const live = invoices.filter((i) => i.status !== 'cancelled');
  res.json({
    customer: c,
    invoices,
    totals: {
      sales: round2(live.reduce((s, i) => s + i.total, 0)),
      received: round2(live.reduce((s, i) => s + i.receivedAmount, 0)),
      balance: round2(live.reduce((s, i) => s + i.balance, 0) + (c.openingBalance || 0)),
      count: live.length,
    },
  });
});

router.post('/', async (req, res) => {
  const c = new Customer();
  apply(c, req.body || {});
  await c.save();
  res.status(201).json(c);
});

router.put('/:id', async (req, res) => {
  const c = await Customer.findById(req.params.id);
  if (!c) throw new HttpError(404, 'Customer not found');
  apply(c, req.body || {});
  await c.save();
  res.json(c);
});

router.delete('/:id', async (req, res) => {
  if (await Invoice.exists({ customer: req.params.id })) {
    await Customer.findByIdAndUpdate(req.params.id, { active: false });
    return res.json({ ok: true, deactivated: true });
  }
  await Customer.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
