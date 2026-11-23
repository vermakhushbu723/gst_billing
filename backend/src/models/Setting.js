import mongoose from 'mongoose';

// Editable master lists. key 'main' holds the defaults; each company gets its
// own copy (key 'company:<id>') the first time it is read.
export const DEFAULT_SETTINGS = {
  units: ['KGS', 'NOS', 'PCS', 'BAGS', 'BOX', 'LTR', 'TON', 'MTR', 'DOZ', 'SET'],
  gstRates: [0, 0.25, 3, 5, 12, 18, 28, 40],
  paymentModes: ['Cash', 'UPI', 'Bank', 'Cheque', 'Card'],
  expenseCategories: ['Electricity', 'Salary', 'Rent', 'Diesel / Fuel', 'Transport', 'Repair & Maintenance', 'Packing Material', 'Water', 'Office', 'Other'],
  partyCategories: ['Retail', 'Wholesale', 'Hotel / Restaurant', 'Bar', 'Caterer', 'Distributor', 'Other'],
};
export const LIST_KEYS = ['units', 'gstRates', 'paymentModes', 'expenseCategories', 'partyCategories'];

const settingSchema = new mongoose.Schema(
  {
    key: { type: String, default: 'main', unique: true },
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', default: null },
    units: { type: [String], default: DEFAULT_SETTINGS.units },
    gstRates: { type: [Number], default: DEFAULT_SETTINGS.gstRates },
    paymentModes: { type: [String], default: DEFAULT_SETTINGS.paymentModes },
    expenseCategories: { type: [String], default: DEFAULT_SETTINGS.expenseCategories },
    partyCategories: { type: [String], default: DEFAULT_SETTINGS.partyCategories },
  },
  { timestamps: true },
);

export const Setting = mongoose.model('Setting', settingSchema);

export const settingsKey = (companyId) => (companyId ? `company:${companyId}` : 'main');

/** Settings for a company (copied from the defaults on first use), or the defaults. */
export async function getSettings(companyId = null) {
  const main = await Setting.findOneAndUpdate({ key: 'main' }, { $setOnInsert: { key: 'main' } }, { upsert: true, new: true, setDefaultsOnInsert: true }).lean();
  if (!companyId) return main;
  const key = settingsKey(companyId);
  const existing = await Setting.findOne({ key }).lean();
  if (existing) return existing;
  const copy = { key, company: companyId };
  for (const k of LIST_KEYS) copy[k] = main[k] ?? DEFAULT_SETTINGS[k];
  return Setting.findOneAndUpdate({ key }, { $setOnInsert: copy }, { upsert: true, new: true }).lean();
}
