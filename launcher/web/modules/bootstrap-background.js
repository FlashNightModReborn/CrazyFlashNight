// Start the chosen portrait as soon as its element exists, while the rest of the front door loads.
(function () {
  'use strict';
  var art = document.getElementById('bg-art');
  var fallback = { file: 'remake-andy.png', side: 'left' };
  function paint(portrait) {
    var url = 'assets/bg/' + portrait.file;
    var image = new Image();
    image.onload = function () {
      document.body.dataset.artSide = portrait.side;
      art.dataset.side = portrait.side;
      art.style.backgroundImage = 'url("' + url + '")';
      performance.mark('bootstrap.welcome_art_applied');
    };
    image.onerror = function () {
      if (portrait.file !== fallback.file) paint(fallback);
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
