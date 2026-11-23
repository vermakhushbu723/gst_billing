import { Router } from 'express';
import crypto from 'node:crypto';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { Customer } from '../models/Customer.js';
import { HttpError, assertOwn } from '../middleware/auth.js';
import { round2 } from '../utils/gst.js';
import { istToday } from '../utils/docs.js';
import { settle } from './invoices.js';
import { money, notify } from '../utils/notify.js';

const router = Router();
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const oid = (v) => new mongoose.Types.ObjectId(String(v));

// Every payment received, across all invoices.
router.get('/', async (req, res) => {
  const { company, customer, from, to, mode } = req.query;
  const match = { docType: 'invoice', status: { $ne: 'cancelled' } };
  if (company && company !== 'all' && mongoose.isValidObjectId(company)) match.company = oid(company);
  if (customer && mongoose.isValidObjectId(customer)) match.customer = oid(customer);
  const pmatch = {};
  if (from || to) {
    pmatch['payments.date'] = {};
    if (from) pmatch['payments.date'].$gte = String(from);
    if (to) pmatch['payments.date'].$lte = String(to);
  }
  if (mode && mode !== 'all') pmatch['payments.mode'] = String(mode);
  const items = await Invoice.aggregate([
    { $match: match },
    { $unwind: '$payments' },
    { $match: pmatch },
    { $sort: { 'payments.date': -1, 'payments._id': -1 } },
    { $limit: 1000 },
    {
      $project: {
        _id: '$payments._id', invoice: '$_id', invoiceNo: 1, invoicePrefix: 1, customer: 1, customerName: '$billTo.name',
        companyName: '$companySnapshot.name', date: '$payments.date', amount: '$payments.amount', mode: '$payments.mode', note: '$payments.note',
      },
    },
  ]);
  const byMode = {};
  for (const p of items) byMode[p.mode || 'Other'] = round2((byMode[p.mode || 'Other'] || 0) + p.amount);
  res.json({ items, total: round2(items.reduce((s, p) => s + p.amount, 0)), byMode });
});

// Customer pays an amount; it settles the oldest unpaid invoices first.
router.post('/', async (req, res) => {
  const { customer, company, mode, note } = req.body || {};
  const amount = round2(Number(req.body?.amount) || 0);
  if (!mongoose.isValidObjectId(customer)) throw new HttpError(400, 'Select a customer');
  const custDoc = assertOwn(req, await Customer.findById(customer).select('name company').lean());
  if (!(amount > 0)) throw new HttpError(400, 'Amount must be more than 0');
  const date = DATE_RE.test(req.body?.date || '') ? req.body.date : istToday();
  const filter = { customer, docType: 'invoice', status: { $in: ['unpaid', 'partial'] } };
  if (company && company !== 'all' && mongoose.isValidObjectId(company)) filter.company = company;
  const invoices = await Invoice.find(filter).sort({ invoiceDate: 1, invoiceNo: 1 });
  const due = round2(invoices.reduce((s, i) => s + i.balance, 0));
  if (due <= 0) throw new HttpError(400, 'This customer has no pending invoice');
  if (amount > due + 0.005) throw new HttpError(400, `Amount is more than the pending ₹${due.toFixed(2)}`);
  const receipt = crypto.randomBytes(4).toString('hex').toUpperCase();
  let left = amount;
  const allocated = [];
  for (const inv of invoices) {
    if (left <= 0) break;
    const part = round2(Math.min(left, inv.balance));
    if (part <= 0) continue;
    inv.payments.push({ date, amount: part, mode: mode || 'Cash', note: [note, `Receipt ${receipt}`].filter(Boolean).join(' • ') });
    settle(inv);
    await inv.save();
    allocated.push({ invoice: inv._id, invoiceNo: `${inv.invoicePrefix || ''}${inv.invoiceNo}`, amount: part });
    left = round2(left - part);
  }
  const cust = custDoc;
  await notify({ type: 'payment', severity: 'success', actor: req.user._id, company: cust.company || invoices[0]?.company, link: `/customers/${customer}`,
    title: `Payment received ${money(amount)}`, body: `${cust?.name || ''} • ${mode || 'Cash'} • ${allocated.map((a) => '#' + a.invoiceNo).join(', ')}` });
  res.status(201).json({ receipt, amount, allocated });
});

export default router;
