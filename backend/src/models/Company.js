import mongoose from 'mongoose';

const bankSchema = new mongoose.Schema(
  {
    accountName: { type: String, default: '' },
    ifsc: { type: String, default: '' },
    accountNo: { type: String, default: '' },
    bankName: { type: String, default: '' },
    branch: { type: String, default: '' },
    upiId: { type: String, default: '' },
  },
  { _id: false },
);

const companySchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    tagline: { type: String, default: '', trim: true },
    address: { type: String, default: '', trim: true },
    city: { type: String, default: '', trim: true },
    stateCode: { type: String, default: '27' },
    state: { type: String, default: 'Maharashtra' },
    pincode: { type: String, default: '', trim: true },
    mobile: { type: String, default: '', trim: true },
    email: { type: String, default: '', trim: true },
    gstin: { type: String, default: '', uppercase: true, trim: true },
    pan: { type: String, default: '', uppercase: true, trim: true },
    bank: { type: bankSchema, default: () => ({}) },
    terms: { type: [String], default: [] },
    invoicePrefix: { type: String, default: '' },
    docPrefixes: { type: Object, default: () => ({ quotation: 'QT-', credit_note: 'CN-', challan: 'DC-' }) },
    // Not GST registered → only bills without GST can be made.
    gstRegistered: { type: Boolean, default: true },
    nonGstPrefixes: { type: Object, default: () => ({ invoice: 'B-', quotation: 'EST-', credit_note: 'SR-', challan: 'NDC-' }) },
    nextBillNo: { type: Number, default: 1 }, // next number of the without-GST bill series
    nextInvoiceNo: { type: Number, default: 1 },
    dueDays: { type: Number, default: 15 },
    color: { type: String, default: '#000000' },
    // Images as data URLs (small PNG/JPEG); excluded from list responses.
    logo: { type: String, default: '', select: false },
    signature: { type: String, default: '', select: false },
    active: { type: Boolean, default: true },
  },
  { timestamps: true },
);

export const Company = mongoose.model('Company', companySchema);
