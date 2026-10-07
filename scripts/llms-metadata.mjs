export function metadataText(value, field) {
  const text = String(value || "");
  if (/[<>]/.test(text)) throw new Error(`${field} must be plain text`);
  return text
    .replace(/&(?:mdash|amp|nbsp|#39|quot);/g, (entity) => ({ "&mdash;": "-", "&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": '"' })[entity])
    .replace(/\s+/g, " ")
    .trim();
}

export function descriptionMetadata(html) {
  // A quoted value may contain the other quote character or a > character.
  // Match the complete value before inspecting another attribute or meta tag.
  for (const [tag] of html.matchAll(/<meta\b(?:[^"'<>]|"[^"]*"|'[^']*')*>/gi)) {
    const attributes = new Map();
    for (const match of tag.matchAll(/([^\s="'<>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g)) {
      const name = match[1].toLowerCase();
      if (!attributes.has(name)) attributes.set(name, match[2] ?? match[3] ?? match[4]);
    }
    if (attributes.get("name")?.toLowerCase() === "description") {
      return metadataText(attributes.get("content"), "description");
    }
  }
  return "";
}
