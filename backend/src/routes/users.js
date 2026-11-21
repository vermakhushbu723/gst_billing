import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { User } from '../models/User.js';
import { HttpError, requireAdmin } from '../middleware/auth.js';
import { publicUser } from './auth.js';

const router = Router();
router.use(requireAdmin);

router.get('/', async (_req, res) => {
  const users = await User.find().sort({ createdAt: 1 });
  res.json(users.map(publicUser));
});

router.post('/', async (req, res) => {
  const { name, email, phone, password, role } = req.body || {};
  if (!name || !email || !password) throw new HttpError(400, 'Name, email and password required');
  if (String(password).length < 6) throw new HttpError(400, 'Password must be at least 6 characters');
  const user = await User.create({
    name,
    email,
    phone: phone || '',
    role: role === 'admin' ? 'admin' : 'staff',
    passwordHash: await bcrypt.hash(String(password), 10),
  });
  res.status(201).json(publicUser(user));
});

router.put('/:id', async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) throw new HttpError(404, 'User not found');
  const { name, email, phone, password, role, active } = req.body || {};
  const isSelf = String(user._id) === String(req.user._id);
  if (name !== undefined) user.name = name;
  if (email !== undefined) user.email = email;
  if (phone !== undefined) user.phone = phone;
  if (role !== undefined && !isSelf) user.role = role === 'admin' ? 'admin' : 'staff';
  if (active !== undefined && !isSelf) user.active = Boolean(active);
  if (password) {
    if (String(password).length < 6) throw new HttpError(400, 'Password must be at least 6 characters');
    user.passwordHash = await bcrypt.hash(String(password), 10);
  }
  await user.save();
  res.json(publicUser(user));
});

router.delete('/:id', async (req, res) => {
  if (String(req.params.id) === String(req.user._id)) throw new HttpError(400, 'You cannot delete yourself');
  await User.findByIdAndDelete(req.params.id);
  res.json({ ok: true });
});

export default router;
