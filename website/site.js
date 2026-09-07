(() => {
  const preference = window.matchMedia('(prefers-color-scheme: dark)');
  let selected = null;
  try { selected = localStorage.getItem('rotype-theme'); } catch { /* Storage can be disabled. */ }
  if (!['light', 'dark'].includes(selected)) selected = null;
  const button = document.querySelector('.theme');
  function render() {
    const dark = selected ? selected === 'dark' : preference.matches;
    if (selected) document.documentElement.dataset.theme = selected;
    else delete document.documentElement.dataset.theme;
    button?.setAttribute('aria-label', dark ? '切换为浅色' : '切换为深色');
    const image = document.querySelector('#hero-image');
    if (image) {
      const source = `/assets/settings-${dark ? 'dark' : 'light'}.webp`;
      image.src = source;
      const pictureSource = image.parentElement.querySelector('source');
      if (pictureSource) pictureSource.srcset = source;
    }
  }
  button?.addEventListener('click', () => {
    const dark = selected ? selected === 'dark' : preference.matches;
    selected = dark ? 'light' : 'dark';
    try { localStorage.setItem('rotype-theme', selected); } catch { /* No persistence is also fine. */ }
    render();
  });
  preference.addEventListener('change', render);
  document.querySelectorAll('.mobile-nav a').forEach(link => {
    link.addEventListener('click', () => { link.closest('details').open = false; });
  });
  document.addEventListener('keydown', event => {
    const menu = document.querySelector('.mobile-nav');
    if (event.key === 'Escape' && menu?.open) {
      menu.open = false;
      menu.querySelector('summary').focus();
    }
  });
  render();
})();
