// Sales document types. All share one collection and one form; numbering is
// separate per company and per type.
export const DOC_TYPES = ['invoice', 'quotation', 'credit_note', 'challan'];

export const DEFAULT_PREFIXES = { quotation: 'QT-', credit_note: 'CN-', challan: 'DC-' };

export const docTypeOf = (v) => (DOC_TYPES.includes(v) ? v : 'invoice');

export function prefixFor(company, docType) {
  if (docType === 'invoice') return company?.invoicePrefix || '';
  const p = company?.docPrefixes?.[docType];
  return p === undefined || p === null ? DEFAULT_PREFIXES[docType] : p;
}

// "Today" in India, as YYYY-MM-DD.
export const istToday = () => new Date(Date.now() + 330 * 60 * 1000).toISOString().slice(0, 10);

export function addDays(ymd, days) {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
