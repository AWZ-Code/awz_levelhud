const hud = document.getElementById('levelHud');
const rankNumber = document.getElementById('rankNumber');
const xpFillClip = document.getElementById('xpFillClip');
const xpMetaValue = document.getElementById('xpMetaValue');

const toast = document.getElementById('levelToast');
const toastTitle = document.getElementById('levelToastTitle');
const toastOld = document.getElementById('levelToastOld');
const toastNew = document.getElementById('levelToastNew');

const state = {
  visible: false,
  level: 1,
  progress: 0,
  currentXp: 0,
  nextXp: 100,
};

let toastTimer = null;

const clamp = (value, min, max) => Math.min(max, Math.max(min, Number(value) || 0));

function render() {
  const levelText = String(Math.max(1, Math.floor(state.level || 1)));
  const digits = Math.min(3, levelText.length);

  rankNumber.textContent = levelText;
  rankNumber.setAttribute('data-digits', String(digits));

  xpFillClip.style.width = `${clamp(state.progress, 0, 100)}%`;
  xpMetaValue.textContent = `${Math.floor(state.currentXp)} / ${Math.floor(state.nextXp)} XP`;
  hud.classList.toggle('is-visible', !!state.visible);
  hud.setAttribute('aria-hidden', state.visible ? 'false' : 'true');
}

function patch(payload = {}) {
  if (payload.level !== undefined) state.level = payload.level;
  if (payload.progress !== undefined) state.progress = payload.progress;
  if (payload.currentXp !== undefined) state.currentXp = payload.currentXp;
  if (payload.nextXp !== undefined) state.nextXp = payload.nextXp;
  if (payload.visible !== undefined) state.visible = !!payload.visible;
  render();
}

function hideToast() {
  toast.classList.remove('is-visible', 'is-up', 'is-down');
  toast.setAttribute('aria-hidden', 'true');
}

function showToast(payload = {}) {
  const kind = payload.toastType === 'down' ? 'down' : 'up';
  const oldLevel = Math.max(1, Math.floor(Number(payload.oldLevel) || 1));
  const newLevel = Math.max(1, Math.floor(Number(payload.newLevel) || 1));
  const duration = Math.max(500, Math.floor(Number(payload.duration) || 2600));

  toastTitle.textContent = kind === 'down' ? 'LIVELLO RIDOTTO' : 'LIVELLO AUMENTATO';
  toastOld.textContent = String(oldLevel);
  toastNew.textContent = String(newLevel);

  toast.classList.remove('is-up', 'is-down');
  toast.classList.add(kind === 'down' ? 'is-down' : 'is-up');
  toast.classList.add('is-visible');
  toast.setAttribute('aria-hidden', 'false');

  if (toastTimer) {
    clearTimeout(toastTimer);
  }

  toastTimer = setTimeout(() => {
    hideToast();
    toastTimer = null;
  }, duration);
}

window.addEventListener('message', (event) => {
  const data = event.data || {};

  switch (data.action) {
    case 'level:init':
      render();
      break;

    case 'level:show':
      patch({ ...data, visible: true });
      break;

    case 'level:update':
      patch(data);
      break;

    case 'level:hide':
      patch({ visible: false });
      break;

    case 'level:toast':
      showToast(data);
      break;
  }
});

window.addEventListener('load', render);
render();