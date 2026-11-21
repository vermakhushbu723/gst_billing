import mongoose from 'mongoose';

const itemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product' },
    name: String,
    description: String,
    hsn: String,
    unit: String,
    qty: Number,
    rate: Number,
    gstRate: Number,
    taxable: Number,
    tax: Number,
    amount: Number,
  },
  { _id: false },
);

const paymentSchema = new mongoose.Schema({
  date: String,
  amount: Number,
  mode: { type: String, default: 'Cash' },
  note: { type: String, default: '' },
});

const taxRowSchema = new mongoose.Schema(
  { rate: Number, taxable: Number, cgst: Number, sgst: Number, igst: Number },
  { _id: false },
);

const invoiceSchema = new mongoose.Schema(
  {
    docType: { type: String, enum: ['invoice', 'quotation', 'credit_note', 'challan'], default: 'invoice' },
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    refInvoiceNo: { type: String, default: '' }, // credit note: against which invoice
    convertedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'Invoice' },
    convertedFrom: { type: mongoose.Schema.Types.ObjectId, ref: 'Invoice' },
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer', required: true },
    invoiceNo: { type: Number, required: true },
    invoicePrefix: { type: String, default: '' },
    invoiceDate: { type: String, required: true }, // YYYY-MM-DD
    dueDate: { type: String, default: '' },
    // Snapshots so editing a company or customer later never changes old invoices.
    companySnapshot: { type: Object, default: {} },
    billTo: { type: Object, default: {} },
    shipTo: { type: Object, default: {} },
    placeOfSupply: { type: String, default: '' },
    placeOfSupplyCode: { type: String, default: '' },
    intraState: { type: Boolean, default: true },
    items: [itemSchema],
    taxSummary: [taxRowSchema],
    totalQty: Number,
    taxableAmount: Number,
    totalTax: Number,
    cgst: Number,
    sgst: Number,
    igst: Number,
    total: Number,
    receivedAmount: { type: Number, default: 0 },
    balance: { type: Number, default: 0 },
    // invoice: unpaid/partial/paid; quotation & challan: open/converted; credit note: issued
    status: { type: String, enum: ['unpaid', 'partial', 'paid', 'cancelled', 'open', 'converted', 'issued'], default: 'unpaid' },
    payments: [paymentSchema],
    notes: { type: String, default: '' },
    vehicleNo: { type: String, default: '' },
    poNumber: { type: String, default: '' },
    shareToken: { type: String, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);

invoiceSchema.index({ company: 1, docType: 1, invoiceNo: 1 }, { unique: true });
invoiceSchema.index({ invoiceDate: -1 });
invoiceSchema.index({ customer: 1 });

export const Invoice = mongoose.model('Invoice', invoiceSchema);
