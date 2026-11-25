// Start the chosen portrait as soon as its element exists, while the rest of the front door loads.
(function () {
  'use strict';
  var art = document.getElementById('bg-art');
  var fallback = { file: 'remake-andy.png', side: 'left' };
  var revealed = false;
  var sideApplied = false;
  var reduced = false;
  try { reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}

  if (art) art.classList.add('art-pending');
  if (document.body) document.body.classList.add('art-side-pending');

  var sideFallbackTimer = setTimeout(function () {
    if (!sideApplied && document.body) document.body.classList.remove('art-side-pending');
  }, 140);

  var heroIntroTriggered = false;

  function triggerHeroIntro() {
    if (heroIntroTriggered || reduced) return;
    var hero = document.querySelector('#view-welcome .hero');
    if (!hero) return;
    heroIntroTriggered = true;
    hero.classList.add('hero-intro');
    setTimeout(function () { hero.classList.remove('hero-intro'); }, 480);
  }

  function applySide(side) {
    sideApplied = true;
    clearTimeout(sideFallbackTimer);
    if (document.body) {
      document.body.dataset.artSide = side;
      document.body.classList.remove('art-side-pending');
    }
    if (art) art.dataset.side = side;
    triggerHeroIntro();
  }

  function triggerReveal() {
    if (revealed || !art) return;
    revealed = true;
    art.classList.remove('art-pending');
    if (reduced) return;
    art.classList.remove('reveal');
    void art.offsetWidth;
    art.classList.add('reveal');
    var scan = document.getElementById('art-scan');
    if (scan) {
      scan.classList.remove('run');
      void scan.offsetWidth;
      scan.classList.add('run');
    }
  }

  function paint(portrait) {
    applySide(portrait.side);
    var url = 'assets/bg/' + portrait.file;
    var image = new Image();
    image.onload = function () {
      if (art) {
        art.dataset.side = portrait.side;
        art.style.backgroundImage = 'url("' + url + '")';
      }
      if (document.body) document.body.dataset.artSide = portrait.side;
      triggerReveal();
      performance.mark('bootstrap.welcome_art_applied');
    };
    image.onerror = function () {
      if (portrait.file !== fallback.file) paint(fallback);
      else if (art) art.classList.remove('art-pending');
    };
    image.src = url;
  }

  fetch('assets/bg/portraits.json').then(function (response) {
    if (!response.ok) throw new Error(String(response.status));
    return response.json();
  }).then(function (catalog) {
    var entries = catalog.portraits.filter(function (p) {
      return p && /^(left|right)$/.test(p.side) && /^remake-[a-z0-9-]+\.png$/.test(p.file);
    });
    paint(entries.length ? entries[Math.floor(Math.random() * entries.length)] : fallback);
  }).catch(function () { paint(fallback); });
})();
