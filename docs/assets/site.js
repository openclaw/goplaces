const buttons = document.querySelectorAll("[data-copy]");

buttons.forEach((button) => {
  button.addEventListener("click", async () => {
    const target = document.querySelector(button.dataset.copy);
    if (!target) return;
    const text = target.innerText.trim();
    try {
      await navigator.clipboard.writeText(text);
      const old = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = old;
      }, 1200);
    } catch {
      button.textContent = "Select";
    }
  });
});
