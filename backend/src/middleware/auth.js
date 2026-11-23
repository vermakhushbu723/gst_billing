import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { User } from '../models/User.js';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const signToken = (user) =>
  jwt.sign({ sub: String(user._id), role: user.role }, config.jwtSecret, { expiresIn: '30d' });

/** Super admin: an admin not tied to a company. Sees and manages every company. */
export const isSuperAdmin = (user) => user?.role === 'admin' && !user.company;

export async function requireAuth(req, _res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) throw new HttpError(401, 'Login required');
  let payload;
  try {
    payload = jwt.verify(token, config.jwtSecret);
  } catch {
    throw new HttpError(401, 'Session expired, please login again');
  }
  const user = await User.findById(payload.sub);
  if (!user || !user.active) throw new HttpError(401, 'Account disabled');
  req.user = user;
  req.scope = user.company ? String(user.company) : null;
  next();
}

/**
 * Company login: a user tied to a company only ever works on that company.
 * Their company replaces whatever `company` the request asked for, in the
 * query string and in the body, so every list, report and write is limited
 * to their own data.
 */
export function applyScope(req, _res, next) {
  if (req.scope) {
    Object.defineProperty(req, 'query', {
      value: { ...req.query, company: req.scope },
      writable: true,
      configurable: true,
      enumerable: true,
    });
    if (req.body && typeof req.body === 'object' && !Array.isArray(req.body)) req.body.company = req.scope;
  }
  next();
}

/** 404 when a company user opens another company's record. */
export function assertOwn(req, doc, field = 'company') {
  if (!doc) throw new HttpError(404, 'Not found');
  if (req.scope && String(doc[field]?._id ?? doc[field]) !== req.scope) throw new HttpError(404, 'Not found');
  return doc;
}

/** Admin of their scope: super admin, or admin of their own company. */
export function requireAdmin(req, _res, next) {
  if (req.user?.role !== 'admin') throw new HttpError(403, 'Only admin can do this');
  next();
}

export function requireSuperAdmin(req, _res, next) {
  if (!isSuperAdmin(req.user)) throw new HttpError(403, 'Only the main admin can do this');
  next();
}

export function errorHandler(err, _req, res, _next) {
  let status = err.status || 500;
  let message = err.message || 'Server error';
  if (err.name === 'ValidationError' || err.name === 'CastError') status = 400;
  if (err.code === 11000) {
    status = 409;
    message = err.keyPattern?.invoiceNo
      ? 'This number already exists for this company'
      : err.keyPattern?.email
        ? 'This email is already used by another login'
        : 'Already exists';
  }
  if (err.type === 'entity.too.large') {
    status = 413;
    message = 'File too large';
  }
  if (status >= 500) console.error(err);
  res.status(status).json({ message });
}
