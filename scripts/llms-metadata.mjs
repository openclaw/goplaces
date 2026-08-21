export function metadataText(value, field) {
  const text = String(value || "");
  if (/[<>]/.test(text)) throw new Error(`${field} must be plain text`);
  return text
    .replace(/&(?:mdash|amp|nbsp|#39|quot);/g, (entity) => ({ "&mdash;": "-", "&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": '"' })[entity])
    .replace(/\s+/g, " ")
    .trim();
}
