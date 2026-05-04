// Copy buttons
document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const text = button.dataset.copyText || document.querySelector(button.dataset.copy)?.innerText.trim();
    if (!text) return;
    const original = button.textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select";
    }
    window.setTimeout(() => { button.textContent = original; }, 1300);
  });
});

// Tabs
document.querySelectorAll("[data-tabs]").forEach((group) => {
  const tabs = group.querySelectorAll("[role='tab']");
  const panels = group.querySelectorAll("[role='tabpanel']");
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.setAttribute("aria-selected", t === tab ? "true" : "false"));
      const id = tab.getAttribute("aria-controls");
      panels.forEach((p) => p.classList.toggle("is-active", p.id === id));
    });
  });
});

// Card spotlight follows the cursor
document.querySelectorAll(".card").forEach((card) => {
  card.addEventListener("pointermove", (e) => {
    const rect = card.getBoundingClientRect();
    card.style.setProperty("--mx", `${e.clientX - rect.left}px`);
    card.style.setProperty("--my", `${e.clientY - rect.top}px`);
  });
});

// Smooth-scroll same-page anchor links
document.querySelectorAll('a[href^="#"]').forEach((a) => {
  a.addEventListener("click", (e) => {
    const id = a.getAttribute("href").slice(1);
    if (!id) return;
    const target = document.getElementById(id);
    if (!target) return;
    e.preventDefault();
    target.scrollIntoView({ behavior: "smooth", block: "start" });
    history.replaceState(null, "", `#${id}`);
  });
});
