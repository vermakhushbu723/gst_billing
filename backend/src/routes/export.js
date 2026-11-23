import { Router } from 'express';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { Company } from '../models/Company.js';
import { Customer } from '../models/Customer.js';
import { Product } from '../models/Product.js';
import { Expense } from '../models/Expense.js';
import { HttpError } from '../middleware/auth.js';
import { round2 } from '../utils/gst.js';
import { config } from '../config.js';

// Data for "Export / Download" on the dashboard. Every report comes back as
// { title, columns, rows, totalLabel, total }; the app turns it into Excel, CSV or PDF.
const router = Router();

export const EXPORT_TYPES = ['sales', 'quotations', 'challans', 'credit_notes', 'payments', 'expenses', 'customers', 'products', 'customer_sales', 'item_sales', 'gst'];

const dmy = (s) => (s && s.length >= 10 ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}` : '');
const no = (d) => `${d.invoicePrefix || ''}${d.invoiceNo}`;
const STATUS = { unpaid: 'Unpaid', partial: 'Partially Paid', paid: 'Paid', cancelled: 'Cancelled', open: 'Open', converted: 'Converted', issued: 'Issued' };

function oid(v) {
  return v && v !== 'all' && mongoose.isValidObjectId(v) ? new mongoose.Types.ObjectId(String(v)) : null;
}

function range(q, field) {
  if (!q.from && !q.to) return {};
  const m = {};
  if (q.from) m.$gte = String(q.from);
  if (q.to) m.$lte = String(q.to);
  return { [field]: m };
}

const text = (label) => ({ label, type: 'text' });
const num = (label) => ({ label, type: 'number' });

async function docs(match, q, docType) {
  return Invoice.find({ ...match, docType, status: { $ne: 'cancelled' }, ...range(q, 'invoiceDate') })
    .select('docType invoiceNo invoicePrefix invoiceDate dueDate total totalTax taxableAmount cgst sgst igst balance receivedAmount status customer billTo shareToken payments refInvoiceNo companySnapshot.name')
    .sort({ invoiceDate: 1, invoiceNo: 1 })
    .lean();
}

async function build(type, match, q, base) {
  const link = (d) => (d.shareToken ? `${base}/share/${d.shareToken}` : '');
  switch (type) {
    case 'sales': {
      const rows = await docs(match, q, 'invoice');
      const cats = new Map((await Customer.find({ _id: { $in: rows.map((r) => r.customer) } }).select('category').lean()).map((c) => [String(c._id), c.category || '']));
      return {
        title: 'Sales Summary Report',
        totalLabel: 'Total Sales',
        total: round2(rows.reduce((s, r) => s + r.total, 0)),
        columns: [text('Invoice No'), text('Invoice Date'), text('Contact Name'), num('Amount'), num('Remaining Amount'), text('Invoice Status'), text('Due Date'), text('Invoice Link'), text('Payment Type'), text('Party Category')],
        rows: rows.map((r) => {
          // "cash" when it was fully paid when the invoice was made, otherwise "credit"
          const atOnce = (r.payments || []).filter((p) => p.date === r.invoiceDate).reduce((s, p) => s + p.amount, 0);
          return [no(r), dmy(r.invoiceDate), r.billTo?.name || '', r.total, r.balance, STATUS[r.status] || r.status, dmy(r.dueDate), link(r), atOnce + 0.005 >= r.total ? 'cash' : 'credit', cats.get(String(r.customer)) || ''];
        }),
      };
    }
    case 'quotations':
    case 'challans': {
      const rows = await docs(match, q, type === 'quotations' ? 'quotation' : 'challan');
      return {
        title: type === 'quotations' ? 'Quotations Report' : 'Delivery Challans Report',
        totalLabel: 'Total Amount',
        total: round2(rows.reduce((s, r) => s + r.total, 0)),
        columns: [text(type === 'quotations' ? 'Quotation No' : 'Challan No'), text('Date'), text('Contact Name'), num('Taxable Amount'), num('GST'), num('Amount'), text('Status'), ...(type === 'quotations' ? [text('Valid Till')] : []), text('Link')],
        rows: rows.map((r) => [no(r), dmy(r.invoiceDate), r.billTo?.name || '', r.taxableAmount, r.totalTax, r.total, STATUS[r.status] || r.status, ...(type === 'quotations' ? [dmy(r.dueDate)] : []), link(r)]),
      };
    }
    case 'credit_notes': {
      const rows = await docs(match, q, 'credit_note');
      return {
        title: 'Credit Notes (Sales Returns) Report',
        totalLabel: 'Total Credit',
        total: round2(rows.reduce((s, r) => s + r.total, 0)),
        columns: [text('Credit Note No'), text('Date'), text('Contact Name'), text('Against Invoice'), num('Taxable Amount'), num('CGST'), num('SGST'), num('IGST'), num('Amount'), text('Link')],
        rows: rows.map((r) => [no(r), dmy(r.invoiceDate), r.billTo?.name || '', r.refInvoiceNo || '', r.taxableAmount, r.cgst, r.sgst, r.igst, r.total, link(r)]),
      };
    }
    case 'payments': {
      const items = await Invoice.aggregate([
        { $match: { ...match, docType: 'invoice', status: { $ne: 'cancelled' } } },
        { $unwind: '$payments' },
        { $match: range(q, 'payments.date') },
        { $sort: { 'payments.date': 1 } },
      ]);
      return {
        title: 'Payments Received Report',
        totalLabel: 'Total Received',
        total: round2(items.reduce((s, p) => s + p.payments.amount, 0)),
        columns: [text('Date'), text('Invoice No'), text('Contact Name'), num('Amount'), text('Payment Mode'), text('Note')],
        rows: items.map((p) => [dmy(p.payments.date), no(p), p.billTo?.name || '', p.payments.amount, p.payments.mode || '', p.payments.note || '']),
      };
    }
    case 'expenses': {
      const items = await Expense.find({ ...match, ...range(q, 'date') }).sort({ date: 1 }).lean();
      const names = new Map((await Company.find().select('name').lean()).map((c) => [String(c._id), c.name]));
      return {
        title: 'Expenses Report',
        totalLabel: 'Total Expenses',
        total: round2(items.reduce((s, e) => s + e.amount, 0)),
        columns: [text('Date'), text('Category'), num('Amount'), text('Paid By'), text('Paid To'), text('Note'), text('Company')],
        rows: items.map((e) => [dmy(e.date), e.category, e.amount, e.mode || '', e.paidTo || '', e.note || '', names.get(String(e.company)) || '']),
      };
    }
    case 'customers': {
      const list = await Customer.find({ ...match, active: true }).sort({ name: 1 }).lean();
      const dues = await Invoice.aggregate([
        { $match: { ...match, status: { $ne: 'cancelled' }, docType: { $in: ['invoice', 'credit_note'] } } },
        {
          $group: {
            _id: '$customer',
            sales: { $sum: { $cond: [{ $eq: ['$docType', 'invoice'] }, '$total', 0] } },
            balance: { $sum: { $cond: [{ $eq: ['$docType', 'credit_note'] }, { $multiply: ['$total', -1] }, '$balance'] } },
          },
        },
      ]);
      const map = new Map(dues.map((d) => [String(d._id), d]));
      return {
        title: 'Customers (Parties) Report',
        totalLabel: 'Total Receivable',
        total: round2(list.reduce((s, c) => s + (map.get(String(c._id))?.balance || 0) + (c.openingBalance || 0), 0)),
        columns: [text('Name'), text('Mobile'), text('Email'), text('GSTIN'), text('PAN'), text('State'), text('Party Category'), text('Billing Address'), num('Total Sales'), num('Receivable')],
        rows: list.map((c) => [c.name, c.phone || '', c.email || '', c.gstin || '', c.pan || '', c.state || '', c.category || '', c.billingAddress || '',
          round2(map.get(String(c._id))?.sales || 0), round2((map.get(String(c._id))?.balance || 0) + (c.openingBalance || 0))]),
      };
    }
    case 'products': {
      const list = await Product.find({ ...match, active: true }).sort({ name: 1 }).lean();
      return {
        title: 'Products / Items Report',
        totalLabel: 'Total Products',
        total: list.length,
        columns: [text('Name'), text('HSN/SAC'), text('Unit'), num('Rate'), num('GST %'), text('Description')],
        rows: list.map((p) => [p.name, p.hsn || '', p.unit || '', p.rate, p.gstRate, p.description || '']),
      };
    }
    case 'customer_sales': {
      const rows = await docs(match, q, 'invoice');
      const by = new Map();
      for (const r of rows) {
        const k = String(r.customer);
        const x = by.get(k) || { name: r.billTo?.name || '', gstin: r.billTo?.gstin || '', count: 0, taxable: 0, tax: 0, total: 0, balance: 0 };
        x.count += 1; x.taxable += r.taxableAmount; x.tax += r.totalTax; x.total += r.total; x.balance += r.balance;
        by.set(k, x);
      }
      const list = [...by.values()].sort((a, b) => b.total - a.total);
      return {
        title: 'Customer-wise Sales Report',
        totalLabel: 'Total Sales',
        total: round2(list.reduce((s, c) => s + c.total, 0)),
        columns: [text('Contact Name'), text('GSTIN'), num('Invoices'), num('Taxable Amount'), num('GST'), num('Amount'), num('Remaining Amount')],
        rows: list.map((c) => [c.name, c.gstin, c.count, round2(c.taxable), round2(c.tax), round2(c.total), round2(c.balance)]),
      };
    }
    case 'item_sales': {
      const rows = await Invoice.find({ ...match, docType: 'invoice', status: { $ne: 'cancelled' }, ...range(q, 'invoiceDate') }).select('items').lean();
      const by = new Map();
      for (const r of rows) {
        for (const it of r.items || []) {
          const k = `${(it.name || '').toUpperCase()}|${it.unit || ''}`;
          const x = by.get(k) || { name: it.name, hsn: it.hsn || '', unit: it.unit || '', qty: 0, taxable: 0, tax: 0, amount: 0 };
          x.qty += it.qty; x.taxable += it.taxable; x.tax += it.tax; x.amount += it.amount;
          by.set(k, x);
        }
      }
      const list = [...by.values()].sort((a, b) => b.amount - a.amount);
      return {
        title: 'Item-wise Sales Report',
        totalLabel: 'Total Sales',
        total: round2(list.reduce((s, i) => s + i.amount, 0)),
        columns: [text('Item'), text('HSN/SAC'), num('Quantity'), text('Unit'), num('Taxable Amount'), num('GST'), num('Amount')],
        rows: list.map((i) => [i.name, i.hsn, round2(i.qty), i.unit, round2(i.taxable), round2(i.tax), round2(i.amount)]),
      };
    }
    case 'gst': {
      const [sales, credits] = await Promise.all([docs(match, q, 'invoice'), docs(match, q, 'credit_note')]);
      const rates = new Map();
      const add = (list, sign) => {
        for (const r of list) {
          for (const t of r.taxSummary || []) {
            const x = rates.get(t.rate) || { taxable: 0, cgst: 0, sgst: 0, igst: 0 };
            x.taxable += sign * t.taxable; x.cgst += sign * t.cgst; x.sgst += sign * t.sgst; x.igst += sign * t.igst;
            rates.set(t.rate, x);
          }
        }
      };
      // docs() does not select taxSummary, so fetch it here
      const withTax = async (list) => Invoice.find({ _id: { $in: list.map((r) => r._id) } }).select('taxSummary').lean();
      add(await withTax(sales), 1);
      add(await withTax(credits), -1);
      const list = [...rates.entries()].sort((a, b) => a[0] - b[0]);
      const totalTax = round2(list.reduce((s, [, x]) => s + x.cgst + x.sgst + x.igst, 0));
      return {
        title: 'GST Summary (net of credit notes)',
        totalLabel: 'Total GST',
        total: totalTax,
        columns: [text('GST Rate'), num('Taxable Amount'), num('CGST'), num('SGST'), num('IGST'), num('Total GST')],
        rows: list.map(([rate, x]) => [`${rate}%`, round2(x.taxable), round2(x.cgst), round2(x.sgst), round2(x.igst), round2(x.cgst + x.sgst + x.igst)]),
      };
    }
    default:
      throw new HttpError(400, 'Unknown report');
  }
}

router.get('/:type', async (req, res) => {
  const type = String(req.params.type);
  if (!EXPORT_TYPES.includes(type)) throw new HttpError(400, 'Unknown report');
  const companyId = oid(req.query.company); // forced to the user's company for company logins
  const match = companyId ? { company: companyId } : {};
  const company = companyId ? await Company.findById(companyId).select('name mobile').lean() : null;
  const base = config.publicUrl || `${req.protocol}://${req.get('host')}`;
  const report = await build(type, match, req.query, base);
  res.json({
    type,
    companyName: company?.name || 'All Companies',
    phone: company?.mobile || '',
    from: req.query.from || '',
    to: req.query.to || '',
    ...report,
  });
});

export default router;
