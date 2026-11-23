import { Router } from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import multer from 'multer';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { Company } from '../models/Company.js';
import { Customer } from '../models/Customer.js';
import { HttpError, assertOwn, requireAdmin } from '../middleware/auth.js';
import { computeInvoice, paymentStatus, round2 } from '../utils/gst.js';
import { stateName } from '../utils/states.js';
import { addDays, docTypeOf, istToday, prefixFor } from '../utils/docs.js';
import { config } from '../config.js';
import { docLabel, docNo, money, notify } from '../utils/notify.js';

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

/** Sets received/balance/status. Only invoices carry payments. */
export function settle(inv) {
  if (inv.docType && inv.docType !== 'invoice') {
    inv.payments = [];
    inv.receivedAmount = 0;
    inv.balance = 0;
    if (!['cancelled', 'converted'].includes(inv.status)) inv.status = inv.docType === 'credit_note' ? 'issued' : 'open';
    return;
  }
  const received = round2((inv.payments || []).reduce((s, p) => s + (Number(p.amount) || 0), 0));
  inv.receivedAmount = received;
  inv.balance = round2(Math.max(0, inv.total - received));
  if (inv.status !== 'cancelled') inv.status = paymentStatus(inv.total, received);
}

async function nextNumber(companyId, docType) {
  const company = await Company.findById(companyId);
  const last = await Invoice.findOne({ company: companyId, docType }).sort({ invoiceNo: -1 }).select('invoiceNo').lean();
  const base = docType === 'invoice' ? company?.nextInvoiceNo || 1 : 1;
  return Math.max(base, (last?.invoiceNo || 0) + 1);
}

// Builds every derived field of a document from the request body.
async function fillInvoice(inv, body) {
  const company = await Company.findById(body.company || inv.company);
  if (!company) throw new HttpError(400, 'Select a company');
  const customer = await Customer.findById(body.customer || inv.customer);
  if (!customer) throw new HttpError(400, 'Select a customer');
  if (customer.company && String(customer.company) !== String(company._id)) throw new HttpError(400, 'This customer belongs to another company');
  if (!Array.isArray(body.items) || !body.items.length) throw new HttpError(400, 'Add at least one item');
  for (const it of body.items) {
    if (!String(it.name || '').trim()) throw new HttpError(400, 'Every item needs a name');
    if (!(Number(it.qty) > 0)) throw new HttpError(400, `Quantity must be more than 0 for ${it.name}`);
    if (Number(it.rate) < 0) throw new HttpError(400, `Rate cannot be negative for ${it.name}`);
  }
  const invoiceDate = body.invoiceDate || inv.invoiceDate;
  if (!DATE_RE.test(invoiceDate || '')) throw new HttpError(400, 'Date is required');
  const dueDate = body.dueDate !== undefined ? body.dueDate : inv.dueDate;
  if (dueDate && !DATE_RE.test(dueDate)) throw new HttpError(400, 'Due date is invalid');

  const posCode = body.placeOfSupplyCode || customer.stateCode || company.stateCode;
  const intraState = posCode === company.stateCode;
  const calc = computeInvoice(body.items, { intraState });

  inv.company = company._id;
  inv.customer = customer._id;
  inv.invoiceDate = invoiceDate;
  inv.dueDate = dueDate || '';
  inv.invoicePrefix = prefixFor(company, inv.docType || 'invoice');
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
  if (body.refInvoiceNo !== undefined) inv.refInvoiceNo = String(body.refInvoiceNo).trim();
  return company;
}

async function bumpCounter(inv) {
  if (inv.docType !== 'invoice') return;
  await Company.updateOne({ _id: inv.company, nextInvoiceNo: { $lte: inv.invoiceNo } }, { $set: { nextInvoiceNo: inv.invoiceNo + 1 } });
}

router.get('/', async (req, res) => {
  const { company, customer, status, from, to } = req.query;
  const q = String(req.query.q || '').trim();
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 30));
  const filter = { docType: req.query.type === 'all' ? { $exists: true } : docTypeOf(req.query.type) };
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
  const [items, total, sum] = await Promise.all([
    Invoice.find(filter)
      .select('docType invoiceNo invoicePrefix invoiceDate dueDate total receivedAmount balance status company customer billTo.name billTo.phone companySnapshot.name')
      .sort({ invoiceDate: -1, invoiceNo: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
    Invoice.countDocuments(filter),
    Invoice.aggregate([
      { $match: { ...filter, ...(filter.company ? { company: new mongoose.Types.ObjectId(String(filter.company)) } : {}), ...(filter.customer ? { customer: new mongoose.Types.ObjectId(String(filter.customer)) } : {}), status: filter.status || { $ne: 'cancelled' } } },
      { $group: { _id: null, total: { $sum: '$total' }, balance: { $sum: '$balance' } } },
    ]),
  ]);
  res.json({ items, total, page, pages: Math.ceil(total / limit), sumTotal: round2(sum[0]?.total || 0), sumBalance: round2(sum[0]?.balance || 0) });
});

router.get('/next-number', async (req, res) => {
  if (!mongoose.isValidObjectId(req.query.company)) throw new HttpError(400, 'company required');
  const company = await Company.findById(req.query.company).lean();
  if (!company) throw new HttpError(404, 'Company not found');
  const docType = docTypeOf(req.query.type);
  res.json({ invoiceNo: await nextNumber(req.query.company, docType), prefix: prefixFor(company, docType), dueDays: company.dueDays ?? 15 });
});

router.get('/:id', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id).lean());
  res.json(inv);
});

router.post('/', async (req, res) => {
  const body = req.body || {};
  const docType = docTypeOf(body.docType);
  const inv = new Invoice({ docType, createdBy: req.user._id, shareToken: crypto.randomBytes(18).toString('hex') });
  const company = await fillInvoice(inv, body);

  if (body.invoiceNo) {
    inv.invoiceNo = Number(body.invoiceNo);
    if (!(inv.invoiceNo > 0)) throw new HttpError(400, 'Number is invalid');
  } else {
    inv.invoiceNo = await nextNumber(company._id, docType);
  }
  const received = docType === 'invoice' ? round2(Number(body.receivedAmount) || 0) : 0;
  inv.payments = received > 0
    ? [{ date: inv.invoiceDate, amount: received, mode: body.paymentMode || 'Cash', note: 'Received with invoice' }]
    : [];
  settle(inv);
  await inv.save();
  await bumpCounter(inv);
  await notify({
    type: inv.docType, severity: 'info', actor: req.user._id, company: inv.company, link: `/invoices/${inv._id}`,
    title: `${docLabel(inv.docType)} #${docNo(inv)} created`,
    body: `${inv.billTo?.name || ''} • ${money(inv.total)} • by ${req.user.name}`,
  });
  if (inv.docType === 'invoice' && inv.receivedAmount > 0) {
    await notify({ type: 'payment', severity: 'success', actor: req.user._id, company: inv.company, link: `/invoices/${inv._id}`,
      title: `Payment received ${money(inv.receivedAmount)}`, body: `${inv.billTo?.name || ''} • Invoice #${docNo(inv)}` });
  }
  res.status(201).json(inv);
});

router.put('/:id', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Document not found');
  if (inv.status === 'converted') throw new HttpError(400, 'Already converted to invoice, it cannot be edited');
  const body = req.body || {};
  await fillInvoice(inv, body);
  if (body.invoiceNo && Number(body.invoiceNo) !== inv.invoiceNo) {
    inv.invoiceNo = Number(body.invoiceNo);
    if (!(inv.invoiceNo > 0)) throw new HttpError(400, 'Number is invalid');
  }
  settle(inv);
  await inv.save();
  await bumpCounter(inv);
  res.json(inv);
});

router.delete('/:id', requireAdmin, async (req, res) => {
  assertOwn(req, await Invoice.findById(req.params.id).select('company').lean());
  const inv = await Invoice.findByIdAndDelete(req.params.id);
  if (inv?.shareToken) await fs.rm(path.join(config.uploadDir, 'pdf', `${inv.shareToken}.pdf`), { force: true });
  res.json({ ok: true });
});

router.post('/:id/cancel', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Document not found');
  inv.status = 'cancelled';
  await inv.save();
  await notify({ type: 'cancelled', severity: 'warning', actor: req.user._id, company: inv.company, link: `/invoices/${inv._id}`,
    title: `${docLabel(inv.docType)} #${docNo(inv)} cancelled`, body: `${inv.billTo?.name || ''} • ${money(inv.total)} • by ${req.user.name}` });
  res.json(inv);
});

router.post('/:id/restore', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Document not found');
  inv.status = inv.convertedTo ? 'converted' : 'unpaid';
  settle(inv);
  await inv.save();
  res.json(inv);
});

// Quotation / delivery challan -> new tax invoice with the same items.
router.post('/:id/convert', async (req, res) => {
  const src = assertOwn(req, await Invoice.findById(req.params.id));
  if (!src) throw new HttpError(404, 'Document not found');
  if (!['quotation', 'challan'].includes(src.docType)) throw new HttpError(400, 'Only quotations and challans can be converted');
  if (src.status !== 'open') throw new HttpError(400, src.status === 'converted' ? 'Already converted to invoice' : 'Document is cancelled');
  const company = await Company.findById(src.company);
  const date = DATE_RE.test(req.body?.invoiceDate || '') ? req.body.invoiceDate : istToday();
  const inv = new Invoice({ docType: 'invoice', createdBy: req.user._id, shareToken: crypto.randomBytes(18).toString('hex'), convertedFrom: src._id });
  await fillInvoice(inv, {
    company: src.company,
    customer: src.customer,
    invoiceDate: date,
    dueDate: company?.dueDays > 0 ? addDays(date, company.dueDays) : '',
    placeOfSupplyCode: src.placeOfSupplyCode,
    items: src.items.map((i) => (i.toObject ? i.toObject() : i)),
    shipTo: src.shipTo,
    notes: src.notes,
    vehicleNo: src.vehicleNo,
    poNumber: src.poNumber,
  });
  inv.invoiceNo = await nextNumber(src.company, 'invoice');
  inv.payments = [];
  settle(inv);
  await inv.save();
  await bumpCounter(inv);
  src.status = 'converted';
  src.convertedTo = inv._id;
  await src.save();
  await notify({ type: 'converted', severity: 'success', actor: req.user._id, company: inv.company, link: `/invoices/${inv._id}`,
    title: `${docLabel(src.docType)} #${docNo(src)} converted to Invoice #${docNo(inv)}`, body: `${inv.billTo?.name || ''} • ${money(inv.total)}` });
  res.status(201).json(inv);
});

router.post('/:id/payments', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Invoice not found');
  if (inv.docType !== 'invoice') throw new HttpError(400, 'Payments can be added only to invoices');
  if (inv.status === 'cancelled') throw new HttpError(400, 'Invoice is cancelled');
  const amount = round2(Number(req.body?.amount) || 0);
  if (!(amount > 0)) throw new HttpError(400, 'Amount must be more than 0');
  const date = DATE_RE.test(req.body?.date || '') ? req.body.date : istToday();
  inv.payments.push({ date, amount, mode: req.body?.mode || 'Cash', note: req.body?.note || '' });
  settle(inv);
  await inv.save();
  await notify({ type: 'payment', severity: 'success', actor: req.user._id, company: inv.company, link: `/invoices/${inv._id}`,
    title: `Payment received ${money(amount)}`, body: `${inv.billTo?.name || ''} • Invoice #${docNo(inv)} • ${req.body?.mode || 'Cash'}` });
  res.json(inv);
});

router.delete('/:id/payments/:pid', async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Invoice not found');
  inv.payments = inv.payments.filter((p) => String(p._id) !== req.params.pid);
  settle(inv);
  await inv.save();
  res.json(inv);
});

// The app renders the PDF and uploads it here, so it can be sent on WhatsApp
// as a link (web/desktop) — on phones the file itself is shared directly.
router.post('/:id/share-pdf', upload.single('pdf'), async (req, res) => {
  const inv = assertOwn(req, await Invoice.findById(req.params.id));
  if (!inv) throw new HttpError(404, 'Document not found');
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
