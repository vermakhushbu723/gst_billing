import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT || 4100),
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/gst_billing',
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-me',
  publicUrl: (process.env.PUBLIC_URL || '').replace(/\/$/, ''),
  corsOrigins: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()).filter(Boolean),
  uploadDir: process.env.UPLOAD_DIR || 'uploads',
  // Folder with the Flutter web build (app/build/web) to serve at "/". Optional.
  webDir: process.env.WEB_DIR || '',
};

if (process.env.NODE_ENV === 'production' && config.jwtSecret === 'dev-secret-change-me') {
  console.error('JWT_SECRET must be set in production');
  process.exit(1);
}
