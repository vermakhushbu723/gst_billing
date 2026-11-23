import { Router } from 'express';
import mongoose from 'mongoose';
import { Setting, getSettings, settingsKey } from '../models/Setting.js';
import { HttpError, requireAdmin } from '../middleware/auth.js';

// Masters (units, GST rates, payment modes, expense and party categories).
// Each company has its own lists; the main admin with "All companies" edits the
// defaults that new companies start from.
const router = Router();

const cleanStrings = (v) => [...new Set((Array.isArray(v) ? v : []).map((s) => String(s).trim()).filter(Boolean))];
const companyOf = (req) => {
  const c = req.scope || req.query.company;
  return c && c !== 'all' && mongoose.isValidObjectId(c) ? String(c) : null;
};

router.get('/', async (req, res) => res.json(await getSettings(companyOf(req))));

router.put('/', requireAdmin, async (req, res) => {
  const b = req.body || {};
  const update = {};
  for (const k of ['units', 'paymentModes', 'expenseCategories', 'partyCategories']) {
    if (b[k] !== undefined) {
      update[k] = cleanStrings(b[k]);
      if (!update[k].length) throw new HttpError(400, `Keep at least one value in ${k}`);
    }
  }
  if (b.gstRates !== undefined) {
    update.gstRates = [...new Set((Array.isArray(b.gstRates) ? b.gstRates : []).map(Number).filter((n) => n >= 0 && n <= 100))].sort((a, c) => a - c);
    if (!update.gstRates.length) throw new HttpError(400, 'Keep at least one GST rate');
  }
  const company = companyOf(req);
  await getSettings(company);
  const s = await Setting.findOneAndUpdate({ key: settingsKey(company) }, { $set: update }, { new: true }).lean();
  res.json(s);
});

export default router;
