'use strict';

const context = cast.framework.CastReceiverContext.getInstance();
const pm = context.getPlayerManager();

// Custom control channel — the phone remote toggles the TV stats overlay here.
const NS = 'urn:x-cast:com.nascinema.control';

const $ = (id) => document.getElementById(id);
const els = {
  backdrop: $('backdrop'),
  overlay: $('overlay'),
  clearlogo: $('clearlogo'),
  title: $('title'),
  meta: $('meta'),
  fill: $('fill'),
  elapsed: $('elapsed'),
  remaining: $('remaining'),
  eta: $('eta'),
  pausedTag: $('paused-tag'),
  pausedLogo: $('paused-logo'),
  pausedTitle: $('paused-title'),
  stats: $('stats'),
  clock: $('clock'),
  idle: $('idle'),
  idleBg: $('idle-bg'),
};

let lastBackdrop = '';

function fmt(sec) {
  if (!isFinite(sec) || sec < 0) sec = 0;
  sec = Math.round(sec);
  const h = (sec / 3600) | 0;
  const m = ((sec % 3600) / 60) | 0;
  const s = sec % 60;
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

// Read metadata + customData from the LOAD and paint the overlay.
function applyMeta(media) {
  const md = media.metadata || {};
  const cd = media.customData || {};
  const title = md.title || 'Now Playing';

  els.title.textContent = title;
  els.pausedTitle.textContent = title;

  if (cd.logo) {
    els.clearlogo.src = cd.logo;
    els.clearlogo.style.display = 'block';
    els.title.style.display = 'none';
    els.pausedLogo.src = cd.logo;
    els.pausedLogo.style.display = 'block';
    els.pausedTitle.style.display = 'none';
  } else {
    els.clearlogo.style.display = 'none';
    els.title.style.display = 'block';
    els.pausedLogo.style.display = 'none';
    els.pausedTitle.style.display = 'inline';
  }

  els.meta.textContent = cd.meta || '';

  const bg = cd.backdrop || (md.images && md.images[0] && md.images[0].url) || '';
  if (bg) {
    lastBackdrop = bg;
    els.backdrop.style.backgroundImage = `url("${bg}")`;
  }

  renderStats(cd.source || {}, cd);
}

function renderStats(src, cd) {
  const rows = [];
  const v = [];
  if (src.video_codec) v.push(String(src.video_codec).toUpperCase());
  if (src.width && src.height) v.push(`${src.width}×${src.height}`);
  if (src.hdr) v.push('HDR');
  rows.push(['Stream', cd.stream || 'HLS · server transcode']);
  if (v.length) rows.push(['Source video', v.join(' · ')]);
  if (src.audio_codec) rows.push(['Source audio', String(src.audio_codec).toUpperCase()]);
  if (src.container) rows.push(['Container', String(src.container).toUpperCase()]);
  els.stats.innerHTML =
    '<div class="hdr">STATS FOR NERDS</div>' +
    rows.map((r) => `<div><span class="lbl">${r[0]}</span> &nbsp; ${r[1]}</div>`).join('');
}

function toggleStats(show) {
  els.stats.classList.toggle('hidden', !show);
}

function updateProgress() {
  const cur = pm.getCurrentTimeSec();
  const dur = pm.getDurationSec();
  if (!dur || !isFinite(dur)) return;
  els.fill.style.width = `${Math.min(100, (cur / dur) * 100)}%`;
  els.elapsed.textContent = fmt(cur);
  els.remaining.textContent = '-' + fmt(dur - cur);
  const end = new Date(Date.now() + (dur - cur) * 1000);
  const hh = end.getHours();
  const mm = String(end.getMinutes()).padStart(2, '0');
  const ampm = hh >= 12 ? 'PM' : 'AM';
  const h12 = ((hh + 11) % 12) + 1;
  els.eta.textContent = `Ends at ${h12}:${mm} ${ampm}`;
}

function setState(state) {
  const S = cast.framework.messages.PlayerState;
  const idle = state === S.IDLE || !state;
  els.idle.classList.toggle('hidden', !idle);
  document.body.classList.toggle('paused', state === S.PAUSED || state === S.BUFFERING);
  // Park the clearlogo/title in the corner only while paused.
  els.pausedTag.classList.toggle('hidden', state !== S.PAUSED);
  if (idle && lastBackdrop) {
    els.idleBg.style.backgroundImage = `url("${lastBackdrop}")`;
    els.idleBg.classList.add('show');
  }
}

function tickClock() {
  const now = new Date();
  const hh = now.getHours();
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ampm = hh >= 12 ? 'PM' : 'AM';
  const h12 = ((hh + 11) % 12) + 1;
  els.clock.textContent = `${h12}:${mm} ${ampm}`;
}
tickClock();
setInterval(tickClock, 15000);

pm.setMessageInterceptor(cast.framework.messages.MessageType.LOAD, (req) => {
  if (req.media) applyMeta(req.media);
  toggleStats(false);
  return req;
});

pm.addEventListener(cast.framework.events.EventType.PLAYER_STATE_CHANGED, (e) =>
  setState(e.playerState));
pm.addEventListener(cast.framework.events.EventType.TIME_UPDATE, updateProgress);

context.addCustomMessageListener(NS, (e) => {
  const d = e.data || {};
  if (d.type === 'STATS') toggleStats(!!d.show);
});

setState(cast.framework.messages.PlayerState.IDLE);
context.start();
