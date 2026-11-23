import { Router } from 'express';
import { Customer } from '../models/Customer.js';
import { Invoice } from '../models/Invoice.js';
import { HttpError, assertOwn } from '../middleware/auth.js';
import { Company } from '../models/Company.js';
import mongoose from 'mongoose';
import { stateName } from '../utils/states.js';
import { round2 } from '../utils/gst.js';

const router = Router();
const FIELDS = ['category', 'name', 'phone', 'email', 'gstin', 'pan', 'billingAddress', 'shippingName', 'shippingAddress', 'sameAsBilling', 'stateCode', 'openingBalance', 'active'];

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function apply(doc, body) {
  for (const f of FIELDS) if (body[f] !== undefined) doc[f] = body[f];
  doc.state = stateName(doc.stateCode) || doc.state;
  if (!doc.pan && doc.gstin && doc.gstin.length >= 12) doc.pan = doc.gstin.slice(2, 12);
}

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const filter = { active: true };
  const company = req.query.company;
  if (company && company !== 'all' && mongoose.isValidObjectId(company)) filter.company = company;
  if (q) filter.$or = [{ name: new RegExp(escapeRe(q), 'i') }, { phone: new RegExp(escapeRe(q), 'i') }, { gstin: new RegExp(escapeRe(q), 'i') }];
  const customers = await Customer.find(filter).sort({ name: 1 }).lean();
  // Outstanding balance per customer
  // invoices add to the balance, credit notes reduce it
  const dues = await Invoice.aggregate([
    { $match: { status: { $ne: 'cancelled' }, docType: { $in: ['invoice', 'credit_note'] } } },
    {
      $group: {
        _id: '$customer',
        balance: { $sum: { $cond: [{ $eq: ['$docType', 'credit_note'] }, { $multiply: ['$total', -1] }, '$balance'] } },
        sales: { $sum: { $cond: [{ $eq: ['$docType', 'invoice'] }, '$total', 0] } },
      },
    },
  ]);
  const map = new Map(dues.map((d) => [String(d._id), d]));
  res.json(customers.map((c) => ({
    ...c,
    balance: round2((map.get(String(c._id))?.balance || 0) + (c.openingBalance || 0)),
    sales: round2(map.get(String(c._id))?.sales || 0),
  })));
});

router.get('/:id', async (req, res) => {
  const c = assertOwn(req, await Customer.findById(req.params.id).lean());
  res.json(c);
});

router.get('/:id/statement', async (req, res) => {
  const c = assertOwn(req, await Customer.findById(req.params.id).lean());
  const invoices = await Invoice.find({ customer: c._id })
    .select('docType invoiceNo invoicePrefix invoiceDate dueDate total receivedAmount balance status company companySnapshot.name billTo.name payments')
    .sort({ invoiceDate: -1, invoiceNo: -1 })
    .lean();
  const live = invoices.filter((i) => i.status !== 'cancelled' && i.docType === 'invoice');
  const credits = invoices.filter((i) => i.status !== 'cancelled' && i.docType === 'credit_note');
  const creditTotal = round2(credits.reduce((s, i) => s + i.total, 0));

  // Ledger: invoices (debit), payments and credit notes (credit), oldest first, running balance.
  const entries = [];
  if (c.openingBalance) entries.push({ date: '', type: 'Opening balance', ref: '', debit: c.openingBalance > 0 ? c.openingBalance : 0, credit: c.openingBalance < 0 ? -c.openingBalance : 0 });
  for (const i of live) {
    const no = `${i.invoicePrefix || ''}${i.invoiceNo}`;
    entries.push({ date: i.invoiceDate, type: 'Invoice', ref: no, id: i._id, debit: i.total, credit: 0 });
    for (const p of i.payments || []) entries.push({ date: p.date, type: `Payment (${p.mode || ''})`, ref: no, id: i._id, debit: 0, credit: p.amount });
  }
  for (const i of credits) entries.push({ date: i.invoiceDate, type: 'Credit note', ref: `${i.invoicePrefix || ''}${i.invoiceNo}`, id: i._id, debit: 0, credit: i.total });
  entries.sort((a, b) => (a.date || '').localeCompare(b.date || '') || b.debit - a.debit);
  let run = 0;
  for (const e of entries) {
    run = round2(run + e.debit - e.credit);
    e.balance = run;
  }

  res.json({
    customer: c,
    invoices: invoices.map(({ payments, ...rest }) => rest),
    ledger: entries,
    totals: {
      sales: round2(live.reduce((s, i) => s + i.total, 0)),
      received: round2(live.reduce((s, i) => s + i.receivedAmount, 0)),
      credit: creditTotal,
      balance: round2(live.reduce((s, i) => s + i.balance, 0) - creditTotal + (c.openingBalance || 0)),
      count: live.length,
    },
  });
});

router.post('/', async (req, res) => {
  const c = new Customer();
  const company = req.body?.company;
  if (!mongoose.isValidObjectId(company) || !(await Company.exists({ _id: company }))) throw new HttpError(400, 'Select the company for this customer');
  c.company = company;
  apply(c, req.body || {});
  await c.save();
  res.status(201).json(c);
});

router.put('/:id', async (req, res) => {
  const c = assertOwn(req, await Customer.findById(req.params.id));
  apply(c, req.body || {});
  await c.save();
  res.json(c);
});

router.delete('/:id', async (req, res) => {
  assertOwn(req, await Customer.findById(req.params.id).select('company').lean());
  if (await Invoice.exists({ customer: req.params.id })) {
    await Customer.findByIdAndUpdate(req.params.id, { active: false });
    return res.json({ ok: true, deactivated: true });
  }
  await Customer.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
