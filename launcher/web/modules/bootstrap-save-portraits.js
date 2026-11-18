// Show the team screen's equipment bust only for visible, playable archive rows.
(function () {
  'use strict';
  var bindings = new WeakMap();
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      var element = entry.target;
      observer.unobserve(element);
      var binding = bindings.get(element);
      if (!binding) return;
      var image = document.createElement('img');
      element.replaceChildren(image);
      window.MercPortraits.mount(element, image, binding.merc, {size:224, variant:'card'});
    });
  });

  function release(element) {
    observer.unobserve(element);
    bindings.delete(element);
    window.MercPortraits.clear(element);
    element.replaceChildren();
  }

  function outfit(appearance) {
    // Older Host builds expose three garment names without the full equipment map.
    if (appearance.equipment) return appearance.equipment;
    if (appearance.upper || appearance.lower || appearance.footwear)
      return {body:appearance.upper, leg:appearance.lower, foot:appearance.footwear};
    return null;
  }

  function bind(element, slot, name) {
    var look = slot.appearance || {};
    var equipment = outfit(look);
    var merc = {gender:slot.gender, face:look.face, hair:look.hair, equipment:equipment};
    var valid = !slot.corrupt && !slot.tombstoned && !slot.inconsistent && !!equipment
      && (slot.gender === '男' || slot.gender === '女') && look.face != null && look.face !== ''
      && look.hair != null && look.hair !== '';
    var key = valid ? JSON.stringify(merc) : '';
    element.dataset.initial = Array.from(name)[0] || '·';
    if (valid && bindings.get(element)?.key === key && element.dataset.mercPortraitState !== 'fallback') return;
    release(element);
    if (valid) {
      bindings.set(element, {key:key, merc:merc});
      observer.observe(element);
    }
  }

  window.BootstrapAppearance = {outfit:outfit, bindPortrait:bind, releasePortrait:release};
})();
