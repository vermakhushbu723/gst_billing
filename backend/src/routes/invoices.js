import { Router } from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import multer from 'multer';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { Company } from '../models/Company.js';
import { Customer } from '../models/Customer.js';
import { HttpError, requireAdmin } from '../middleware/auth.js';
import { computeInvoice, paymentStatus, round2 } from '../utils/gst.js';
import { stateName } from '../utils/states.js';
import { config } from '../config.js';

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function companySnapshot(c) {
  return {
    name: c.name, tagline: c.tagline, address: c.address, city: c.city, state: c.state, stateCode: c.stateCode,
    pincode: c.pincode, mobile: c.mobile, email: c.email, gstin: c.gstin, pan: c.pan,
    bank: c.bank ? { ...(c.bank.toObject ? c.bank.toObject() : c.bank) } : {}, terms: [...(c.terms || [])], color: c.color,
  };
}

function settle(inv) {
  const received = round2((inv.payments || []).reduce((s, p) => s + (Number(p.amount) || 0), 0));
  inv.receivedAmount = received;
  inv.balance = round2(Math.max(0, inv.total - received));
  if (inv.status !== 'cancelled') inv.status = paymentStatus(inv.total, received);
}

async function nextNumber(companyId) {
  const company = await Company.findById(companyId);
  const last = await Invoice.findOne({ company: companyId }).sort({ invoiceNo: -1 }).select('invoiceNo').lean();
  return Math.max(company?.nextInvoiceNo || 1, (last?.invoiceNo || 0) + 1);
}

// Builds every derived field of an invoice from the request body.
async function fillInvoice(inv, body) {
  const company = await Company.findById(body.company || inv.company);
  if (!company) throw new HttpError(400, 'Select a company');
  const customer = await Customer.findById(body.customer || inv.customer);
  if (!customer) throw new HttpError(400, 'Select a customer');
  if (!Array.isArray(body.items) || !body.items.length) throw new HttpError(400, 'Add at least one item');
  for (const it of body.items) {
    if (!String(it.name || '').trim()) throw new HttpError(400, 'Every item needs a name');
    if (!(Number(it.qty) > 0)) throw new HttpError(400, `Quantity must be more than 0 for ${it.name}`);
    if (Number(it.rate) < 0) throw new HttpError(400, `Rate cannot be negative for ${it.name}`);
  }
  const invoiceDate = body.invoiceDate || inv.invoiceDate;
  if (!DATE_RE.test(invoiceDate || '')) throw new HttpError(400, 'Invoice date is required');
  const dueDate = body.dueDate !== undefined ? body.dueDate : inv.dueDate;
  if (dueDate && !DATE_RE.test(dueDate)) throw new HttpError(400, 'Due date is invalid');

  const posCode = body.placeOfSupplyCode || customer.stateCode || company.stateCode;
  const intraState = posCode === company.stateCode;
  const calc = computeInvoice(body.items, { intraState });

  inv.company = company._id;
  inv.customer = customer._id;
  inv.invoiceDate = invoiceDate;
  inv.dueDate = dueDate || '';
  inv.invoicePrefix = company.invoicePrefix || '';
  inv.companySnapshot = companySnapshot(company);
  inv.billTo = {
    name: customer.name, address: customer.billingAddress, gstin: customer.gstin, pan: customer.pan,
    phone: customer.phone, state: customer.state, stateCode: customer.stateCode,
  };
  const shipOverride = body.shipTo && (body.shipTo.name || body.shipTo.address);
  inv.shipTo = shipOverride
    ? { name: String(body.shipTo.name || customer.name), address: String(body.shipTo.address || '') }
    : customer.sameAsBilling
      ? { name: customer.name, address: customer.billingAddress }
      : { name: customer.shippingName || customer.name, address: customer.shippingAddress || customer.billingAddress };
  inv.placeOfSupplyCode = posCode;
  inv.placeOfSupply = stateName(posCode);
  inv.intraState = intraState;
  Object.assign(inv, calc);
  if (body.notes !== undefined) inv.notes = String(body.notes);
  if (body.vehicleNo !== undefined) inv.vehicleNo = String(body.vehicleNo);
  if (body.poNumber !== undefined) inv.poNumber = String(body.poNumber);
  return company;
}

router.get('/', async (req, res) => {
  const { company, customer, status, from, to } = req.query;
  const q = String(req.query.q || '').trim();
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 30));
  const filter = {};
  if (company && company !== 'all') filter.company = company;
  if (customer) filter.customer = customer;
  if (status && status !== 'all') filter.status = status === 'due' ? { $in: ['unpaid', 'partial'] } : status;
  if (from || to) {
    filter.invoiceDate = {};
    if (from) filter.invoiceDate.$gte = String(from);
    if (to) filter.invoiceDate.$lte = String(to);
  }
  if (q) {
    const or = [{ 'billTo.name': new RegExp(escapeRe(q), 'i') }];
    if (/^\d+$/.test(q)) or.push({ invoiceNo: Number(q) });
    filter.$or = or;
  }
  const [items, total] = await Promise.all([
    Invoice.find(filter)
      .select('invoiceNo invoicePrefix invoiceDate dueDate total receivedAmount balance status company customer billTo.name billTo.phone companySnapshot.name')
      .sort({ invoiceDate: -1, invoiceNo: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
    Invoice.countDocuments(filter),
  ]);
  res.json({ items, total, page, pages: Math.ceil(total / limit) });
});

router.get('/next-number', async (req, res) => {
  if (!mongoose.isValidObjectId(req.query.company)) throw new HttpError(400, 'company required');
  const company = await Company.findById(req.query.company).lean();
  if (!company) throw new HttpError(404, 'Company not found');
  res.json({ invoiceNo: await nextNumber(req.query.company), prefix: company.invoicePrefix || '', dueDays: company.dueDays ?? 15 });
});

router.get('/:id', async (req, res) => {
  const inv = await Invoice.findById(req.params.id).lean();
  if (!inv) throw new HttpError(404, 'Invoice not found');
  res.json(inv);
});

router.post('/', async (req, res) => {
  const body = req.body || {};
  const inv = new Invoice({ createdBy: req.user._id, shareToken: crypto.randomBytes(18).toString('hex') });
  const company = await fillInvoice(inv, body);

  if (body.invoiceNo) {
    inv.invoiceNo = Number(body.invoiceNo);
    if (!(inv.invoiceNo > 0)) throw new HttpError(400, 'Invoice number is invalid');
  } else {
    inv.invoiceNo = await nextNumber(company._id);
  }
  const received = round2(Number(body.receivedAmount) || 0);
  inv.payments = received > 0
    ? [{ date: inv.invoiceDate, amount: received, mode: body.paymentMode || 'Cash', note: 'Received with invoice' }]
    : [];
  settle(inv);
  await inv.save();
  await Company.updateOne({ _id: company._id, nextInvoiceNo: { $lte: inv.invoiceNo } }, { $set: { nextInvoiceNo: inv.invoiceNo + 1 } });
  res.status(201).json(inv);
});

router.put('/:id', async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  const body = req.body || {};
  const company = await fillInvoice(inv, body);
  if (body.invoiceNo && Number(body.invoiceNo) !== inv.invoiceNo) {
    inv.invoiceNo = Number(body.invoiceNo);
    if (!(inv.invoiceNo > 0)) throw new HttpError(400, 'Invoice number is invalid');
  }
  settle(inv);
  await inv.save();
  await Company.updateOne({ _id: company._id, nextInvoiceNo: { $lte: inv.invoiceNo } }, { $set: { nextInvoiceNo: inv.invoiceNo + 1 } });
  res.json(inv);
});

router.delete('/:id', requireAdmin, async (req, res) => {
  const inv = await Invoice.findByIdAndDelete(req.params.id);
  if (inv?.shareToken) await fs.rm(path.join(config.uploadDir, 'pdf', `${inv.shareToken}.pdf`), { force: true });
  res.json({ ok: true });
});

router.post('/:id/cancel', async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  inv.status = 'cancelled';
  await inv.save();
  res.json(inv);
});

router.post('/:id/restore', async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  inv.status = 'unpaid';
  settle(inv);
  await inv.save();
  res.json(inv);
});

router.post('/:id/payments', async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  if (inv.status === 'cancelled') throw new HttpError(400, 'Invoice is cancelled');
  const amount = round2(Number(req.body?.amount) || 0);
  if (!(amount > 0)) throw new HttpError(400, 'Amount must be more than 0');
  const date = DATE_RE.test(req.body?.date || '') ? req.body.date : new Date().toISOString().slice(0, 10);
  inv.payments.push({ date, amount, mode: req.body?.mode || 'Cash', note: req.body?.note || '' });
  settle(inv);
  await inv.save();
  res.json(inv);
});

router.delete('/:id/payments/:pid', async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  inv.payments = inv.payments.filter((p) => String(p._id) !== req.params.pid);
  settle(inv);
  await inv.save();
  res.json(inv);
});

// The app renders the PDF and uploads it here, so it can be sent on WhatsApp
// as a link (web/desktop) — on phones the file itself is shared directly.
router.post('/:id/share-pdf', upload.single('pdf'), async (req, res) => {
  const inv = await Invoice.findById(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  if (!req.file || !req.file.buffer.subarray(0, 5).toString().startsWith('%PDF')) throw new HttpError(400, 'PDF file required');
  if (!inv.shareToken) {
    inv.shareToken = crypto.randomBytes(18).toString('hex');
    await inv.save();
  }
  const dir = path.join(config.uploadDir, 'pdf');
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, `${inv.shareToken}.pdf`), req.file.buffer);
  const base = config.publicUrl || `${req.protocol}://${req.get('host')}`;
  res.json({ url: `${base}/api/public/pdf/${inv.shareToken}.pdf` });
});

export default router;
