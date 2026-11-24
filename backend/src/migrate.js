import crypto from 'node:crypto';
import { Invoice } from './models/Invoice.js';
import { Company } from './models/Company.js';
import { Customer } from './models/Customer.js';
import { Product } from './models/Product.js';

// Brings data from older versions up to date. Safe to run on every start.
export async function migrate() {
  // v1 had only invoices and a unique index on (company, invoiceNo).
  await Invoice.updateMany({ docType: { $exists: false } }, { $set: { docType: 'invoice' } });
  await Company.updateMany({ docPrefixes: { $exists: false } }, { $set: { docPrefixes: { quotation: 'QT-', credit_note: 'CN-', challan: 'DC-' } } });
  // v4: GST / without-GST flows
  await Invoice.updateMany({ gst: { $exists: false } }, { $set: { gst: true } });
  await Company.updateMany({ gstRegistered: { $exists: false } }, { $set: { gstRegistered: true, nextBillNo: 1, nonGstPrefixes: { invoice: 'B-', quotation: 'EST-', credit_note: 'SR-', challan: 'NDC-' } } });
  await Invoice.syncIndexes();

  // v3: customers and products belong to a company (company logins see only their own).
  const first = await Company.findOne().sort({ createdAt: 1 }).select('_id').lean();
  if (first) {
    for (const c of await Customer.find({ company: null }).select('_id').lean()) {
      const inv = await Invoice.findOne({ customer: c._id }).sort({ createdAt: -1 }).select('company').lean();
      await Customer.updateOne({ _id: c._id }, { $set: { company: inv?.company || first._id } });
    }
    for (const p of await Product.find({ company: null }).select('_id').lean()) {
      const inv = await Invoice.findOne({ 'items.product': p._id }).sort({ createdAt: -1 }).select('company').lean();
      await Product.updateOne({ _id: p._id }, { $set: { company: inv?.company || first._id } });
    }
  }
  // every document gets a public share link
  for (const i of await Invoice.find({ $or: [{ shareToken: { $exists: false } }, { shareToken: null }, { shareToken: '' }] }).select('_id').lean()) {
    await Invoice.updateOne({ _id: i._id }, { $set: { shareToken: crypto.randomBytes(18).toString('hex') } });
  }
}
