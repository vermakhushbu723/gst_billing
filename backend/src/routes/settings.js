import { Router } from 'express';
import { Setting, getSettings } from '../models/Setting.js';
import { HttpError, requireAdmin } from '../middleware/auth.js';

const router = Router();

const cleanStrings = (v) => [...new Set((Array.isArray(v) ? v : []).map((s) => String(s).trim()).filter(Boolean))];

router.get('/', async (_req, res) => res.json(await getSettings()));

router.put('/', requireAdmin, async (req, res) => {
  const b = req.body || {};
  const update = {};
  for (const k of ['units', 'paymentModes', 'expenseCategories']) {
    if (b[k] !== undefined) {
      update[k] = cleanStrings(b[k]);
      if (!update[k].length) throw new HttpError(400, `Keep at least one value in ${k}`);
    }
  }
  if (b.gstRates !== undefined) {
    update.gstRates = [...new Set((Array.isArray(b.gstRates) ? b.gstRates : []).map(Number).filter((n) => n >= 0 && n <= 100))].sort((a, c) => a - c);
    if (!update.gstRates.length) throw new HttpError(400, 'Keep at least one GST rate');
  }
  await getSettings();
  const s = await Setting.findOneAndUpdate({ key: 'main' }, { $set: update }, { new: true }).lean();
  res.json(s);
});

export default router;
