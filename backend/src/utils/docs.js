// Sales document types. All share one collection and one form; numbering is
// separate per company, per type and per flow (with GST / without GST).
export const DOC_TYPES = ['invoice', 'quotation', 'credit_note', 'challan'];

export const DEFAULT_PREFIXES = { quotation: 'QT-', credit_note: 'CN-', challan: 'DC-' };
// Without-GST series ("Bill", "Estimate", "Sales Return", "Delivery Challan")
export const DEFAULT_NONGST_PREFIXES = { invoice: 'B-', quotation: 'EST-', credit_note: 'SR-', challan: 'NDC-' };

export const docTypeOf = (v) => (DOC_TYPES.includes(v) ? v : 'invoice');

/** `gst` query/body value → true (with GST), false (without GST) or null (both). */
export function gstFlag(v) {
  if (v === true || v === 'true' || v === '1' || v === 'gst') return true;
  if (v === false || v === 'false' || v === '0' || v === 'nongst') return false;
  return null;
}

/** Filter for documents of one flow; old documents without the field are GST ones. */
export const gstMatch = (flag) => (flag === null ? {} : flag ? { gst: { $ne: false } } : { gst: false });

export function prefixFor(company, docType, gst = true) {
  if (!gst) {
    const p = company?.nonGstPrefixes?.[docType];
    return p === undefined || p === null ? DEFAULT_NONGST_PREFIXES[docType] : p;
  }
  if (docType === 'invoice') return company?.invoicePrefix || '';
  const p = company?.docPrefixes?.[docType];
  return p === undefined || p === null ? DEFAULT_PREFIXES[docType] : p;
}

const LABELS = {
  true: { invoice: 'Invoice', quotation: 'Quotation', credit_note: 'Credit note', challan: 'Delivery challan' },
  false: { invoice: 'Bill', quotation: 'Estimate', credit_note: 'Sales return', challan: 'Delivery challan' },
};
export const docLabelFor = (docType, gst = true) => LABELS[gst !== false][docType] || 'Invoice';

// "Today" in India, as YYYY-MM-DD.
export const istToday = () => new Date(Date.now() + 330 * 60 * 1000).toISOString().slice(0, 10);

export function addDays(ymd, days) {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
