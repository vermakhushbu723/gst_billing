import { Router } from 'express';
import bcrypt from 'bcryptjs';
import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { Company } from '../models/Company.js';
import { HttpError, assertOwn, requireAdmin } from '../middleware/auth.js';
import { publicUser } from './auth.js';

// Main admin manages every login; a company admin manages only their company's logins.
const router = Router();
router.use(requireAdmin);

/** Company a new/edited login belongs to: forced for company admins, chosen by the main admin. */
async function companyFor(req, requested) {
  if (req.scope) return req.scope;
  if (requested === null || requested === undefined || requested === '' || requested === 'all') return null;
  if (!mongoose.isValidObjectId(requested) || !(await Company.exists({ _id: requested }))) throw new HttpError(400, 'Select a valid company');
  return String(requested);
}

router.get('/', async (req, res) => {
  const filter = {};
  const c = req.scope || req.query.company;
  if (c && c !== 'all' && mongoose.isValidObjectId(c)) filter.company = c;
  const users = await User.find(filter).populate('company', 'name').sort({ createdAt: 1 });
  res.json(users.map(publicUser));
});

router.post('/', async (req, res) => {
  const { name, email, phone, password, role } = req.body || {};
  if (!name || !email || !password) throw new HttpError(400, 'Name, email and password required');
  if (String(password).length < 6) throw new HttpError(400, 'Password must be at least 6 characters');
  const company = await companyFor(req, req.scope ? null : req.body?.loginCompany ?? null);
  const user = await User.create({
    name,
    email,
    phone: phone || '',
    role: role === 'admin' ? 'admin' : 'staff',
    company,
    passwordHash: await bcrypt.hash(String(password), 10),
  });
  await user.populate('company', 'name');
  res.status(201).json(publicUser(user));
});

router.put('/:id', async (req, res) => {
  const user = assertOwn(req, await User.findById(req.params.id));
  const { name, email, phone, password, role, active } = req.body || {};
  const isSelf = String(user._id) === String(req.user._id);
  if (name !== undefined) user.name = name;
  if (email !== undefined) user.email = email;
  if (phone !== undefined) user.phone = phone;
  if (role !== undefined && !isSelf) user.role = role === 'admin' ? 'admin' : 'staff';
  if (active !== undefined && !isSelf) user.active = Boolean(active);
  if (!req.scope && !isSelf && req.body?.loginCompany !== undefined) user.company = await companyFor(req, req.body.loginCompany);
  if (password) {
    if (String(password).length < 6) throw new HttpError(400, 'Password must be at least 6 characters');
    user.passwordHash = await bcrypt.hash(String(password), 10);
  }
  await user.save();
  await user.populate('company', 'name');
  res.json(publicUser(user));
});

router.delete('/:id', async (req, res) => {
  if (String(req.params.id) === String(req.user._id)) throw new HttpError(400, 'You cannot delete yourself');
  const user = assertOwn(req, await User.findById(req.params.id));
  await user.deleteOne();
  res.json({ ok: true });
});

export default router;
