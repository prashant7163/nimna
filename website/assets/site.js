/* nimna.app — the only script. No requests, no storage, no measurement. */
(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Hero: draw the line once when it enters view.
  var hero = document.querySelector('.heroline');
  if (hero) {
    if (reduced) { hero.classList.add('on'); }
    else {
      new IntersectionObserver(function (entries, obs) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { hero.classList.add('on'); obs.disconnect(); }
        });
      }, { threshold: 0.6 }).observe(hero);
    }
  }

  // Relay diagram: send a message through (replayable).
  var box = document.querySelector('.relaybox');
  var btn = document.querySelector('.replay');
  function play() {
    if (!box) return;
    box.classList.remove('play');
    void box.offsetWidth; // restart animation
    box.classList.add('play');
  }
  if (btn) btn.addEventListener('click', play);
  if (box && !reduced) {
    new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { play(); obs.disconnect(); }
      });
    }, { threshold: 0.5 }).observe(box);
  }
})();
