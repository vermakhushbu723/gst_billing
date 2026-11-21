import { Invoice } from './models/Invoice.js';
import { Company } from './models/Company.js';

// Brings data from older versions up to date. Safe to run on every start.
export async function migrate() {
  // v1 had only invoices and a unique index on (company, invoiceNo).
  await Invoice.updateMany({ docType: { $exists: false } }, { $set: { docType: 'invoice' } });
  await Company.updateMany({ docPrefixes: { $exists: false } }, { $set: { docPrefixes: { quotation: 'QT-', credit_note: 'CN-', challan: 'DC-' } } });
  await Invoice.syncIndexes();
}
