import { Router } from 'express';
import bcrypt from 'bcryptjs';
import rateLimit from 'express-rate-limit';
import { User } from '../models/User.js';
import { HttpError, isSuperAdmin, requireAuth, signToken } from '../middleware/auth.js';

const router = Router();

const loginLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: true, legacyHeaders: false });

/** User as the app sees it. `company` may be populated ({_id, name}) or an id. */
export const publicUser = (u) => {
  const c = u.company;
  const companyId = c ? String(c._id ?? c) : null;
  return {
    id: u._id,
    name: u.name,
    email: u.email,
    phone: u.phone,
    role: u.role,
    active: u.active,
    company: companyId,
    companyName: c?.name ?? null,
    superAdmin: isSuperAdmin(u),
  };
};

router.post('/login', loginLimiter, async (req, res) => {
  const email = String(req.body?.email || '').toLowerCase().trim();
  const password = String(req.body?.password || '');
  if (!email || !password) throw new HttpError(400, 'Email and password required');
  const user = await User.findOne({ $or: [{ email }, { phone: email }] }).select('+passwordHash').populate('company', 'name active');
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) throw new HttpError(401, 'Wrong email or password');
  if (!user.active) throw new HttpError(403, 'Account disabled');
  if (user.company && user.company.active === false) throw new HttpError(403, 'This company is deactivated');
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.get('/me', requireAuth, async (req, res) => {
  await req.user.populate('company', 'name active');
  if (req.user.company && req.user.company.active === false) throw new HttpError(403, 'This company is deactivated');
  res.json({ user: publicUser(req.user) });
});

router.put('/me', requireAuth, async (req, res) => {
  const { name, phone } = req.body || {};
  if (name !== undefined) req.user.name = String(name).trim() || req.user.name;
  if (phone !== undefined) req.user.phone = String(phone).trim();
  await req.user.save();
  await req.user.populate('company', 'name');
  res.json({ user: publicUser(req.user) });
});

router.post('/change-password', requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = req.body || {};
  if (!newPassword || String(newPassword).length < 6) throw new HttpError(400, 'New password must be at least 6 characters');
  const user = await User.findById(req.user._id).select('+passwordHash');
  if (!(await bcrypt.compare(String(currentPassword || ''), user.passwordHash))) throw new HttpError(400, 'Current password is wrong');
  user.passwordHash = await bcrypt.hash(String(newPassword), 10);
  await user.save();
  res.json({ ok: true });
});

export default router;
