/* Desert Delivery — reusable retrieval-practice widget.
 *
 * Usage in a lesson:
 *   <div id="q1" class="quiz"></div>
 *   <script src="../assets/quiz.js"></script>
 *   <script>
 *     Quiz.mount('#q1', {
 *       title: 'Where does it go?',
 *       intro: 'Answer from memory. Getting one wrong is worth more than getting it right.',
 *       questions: [
 *         { q: 'Question text',
 *           options: ['Same length', 'Same length', 'Same length', 'Same length'],
 *           answer: 0,
 *           why: 'Shown after answering, right or wrong.' }
 *       ]
 *     });
 *   </script>
 *
 * Options are shuffled on every mount and on every reset, so re-drilling tests recall rather
 * than the position of the button. Feedback is immediate: that is the whole point of the widget.
 *
 * Authoring rule this widget enforces (loudly, in the console): every option in a question must
 * be roughly the same length. Length is a tell, and a tell turns retrieval into pattern-matching.
 */
(function (global) {
  'use strict';

  var STYLE = `
  .quiz { border: 1px solid var(--rule, #ded9cc); border-radius: 4px; margin: 2rem 0;
          background: #fffefb; font-family: var(--sans, sans-serif); }
  .quiz-head { padding: 1rem 1.3rem .8rem; border-bottom: 1px solid var(--rule, #ded9cc); }
  .quiz-head .h { font-size: .68rem; letter-spacing: .14em; text-transform: uppercase;
                  color: var(--accent, #9a5b1e); font-weight: 700; }
  .quiz-head h3 { margin: .35rem 0 0; font-size: 1.05rem; font-family: inherit; }
  .quiz-head p { margin: .45rem 0 0; font-size: .86rem; color: var(--ink-soft, #55524a); }
  .quiz-q { padding: 1.1rem 1.3rem; border-bottom: 1px solid var(--rule, #ded9cc); }
  .quiz-q:last-of-type { border-bottom: none; }
  .quiz-q .stem { font-size: .95rem; margin: 0 0 .8rem; }
  .quiz-q .stem .n { color: var(--ink-faint, #8a867c); font-variant-numeric: tabular-nums;
                     margin-right: .5rem; font-size: .85rem; }
  .quiz-opts { display: grid; gap: .4rem; }
  .quiz-opt { text-align: left; font: inherit; font-size: .88rem; cursor: pointer;
              padding: .55rem .8rem; border: 1px solid var(--rule, #ded9cc); border-radius: 3px;
              background: #fff; color: inherit; transition: background .12s, border-color .12s; }
  .quiz-opt:hover:not(:disabled) { border-color: var(--accent, #9a5b1e); background: #fdf8f1; }
  .quiz-opt:disabled { cursor: default; opacity: .75; }
  .quiz-opt.right { border-color: #3f6b45; background: #f0f6f0; opacity: 1; font-weight: 600; }
  .quiz-opt.wrong { border-color: #9d3a2c; background: #fbf1ef; opacity: 1; }
  .quiz-why { margin: .7rem 0 0; font-size: .85rem; color: var(--ink-soft, #55524a);
              border-left: 2px solid var(--rule, #ded9cc); padding-left: .75rem; }
  .quiz-why b { color: var(--ink, #16150f); }
  .quiz-foot { padding: .85rem 1.3rem; display: flex; justify-content: space-between;
               align-items: center; gap: 1rem; border-top: 1px solid var(--rule, #ded9cc);
               font-size: .84rem; color: var(--ink-soft, #55524a); }
  .quiz-foot button { font: inherit; font-size: .8rem; cursor: pointer; padding: .35rem .8rem;
                      border: 1px solid var(--rule, #ded9cc); border-radius: 3px; background: #fff; }
  .quiz-foot button:hover { border-color: var(--accent, #9a5b1e); }
  `;

  function injectStyleOnce() {
    if (document.getElementById('quiz-widget-style')) return;
    var s = document.createElement('style');
    s.id = 'quiz-widget-style';
    s.textContent = STYLE;
    document.head.appendChild(s);
  }

  function shuffled(n) {
    var a = [];
    for (var i = 0; i < n; i++) a.push(i);
    for (var j = a.length - 1; j > 0; j--) {
      var k = Math.floor(Math.random() * (j + 1));
      var t = a[j]; a[j] = a[k]; a[k] = t;
    }
    return a;
  }

  /* A tell is anything that lets you pick the answer without knowing it. Length is the commonest. */
  function warnOnLengthTells(questions) {
    questions.forEach(function (q, i) {
      var lens = q.options.map(function (o) { return o.length; });
      var spread = Math.max.apply(null, lens) - Math.min.apply(null, lens);
      if (spread > 12) {
        console.warn('[quiz] Q' + (i + 1) + ': option lengths differ by ' + spread +
          ' characters — that is a tell. Even them up. ' + JSON.stringify(lens));
      }
    });
  }

  function mount(target, spec) {
    injectStyleOnce();
    var root = typeof target === 'string' ? document.querySelector(target) : target;
    if (!root) { console.warn('[quiz] no element for', target); return; }
    warnOnLengthTells(spec.questions);

    var answered, correct;

    function render() {
      answered = 0; correct = 0;
      root.className = 'quiz';
      root.innerHTML = '';

      var head = document.createElement('div');
      head.className = 'quiz-head';
      head.innerHTML = '<div class="h">Retrieval practice</div><h3></h3>' +
                       (spec.intro ? '<p></p>' : '');
      head.querySelector('h3').textContent = spec.title || 'Check yourself';
      if (spec.intro) head.querySelector('p').textContent = spec.intro;
      root.appendChild(head);

      var foot = document.createElement('div');
      foot.className = 'quiz-foot';
      var score = document.createElement('span');
      var again = document.createElement('button');
      again.textContent = 'Shuffle and try again';
      again.addEventListener('click', render);

      function updateScore() {
        score.textContent = answered + ' of ' + spec.questions.length + ' answered' +
          (answered ? '  ·  ' + correct + ' right first time' : '');
      }

      spec.questions.forEach(function (q, qi) {
        var box = document.createElement('div');
        box.className = 'quiz-q';

        var stem = document.createElement('p');
        stem.className = 'stem';
        var n = document.createElement('span');
        n.className = 'n';
        n.textContent = (qi + 1) + '.';
        stem.appendChild(n);
        stem.appendChild(document.createTextNode(q.q));
        box.appendChild(stem);

        var opts = document.createElement('div');
        opts.className = 'quiz-opts';
        var buttons = [];
        var done = false;

        shuffled(q.options.length).forEach(function (oi) {
          var b = document.createElement('button');
          b.className = 'quiz-opt';
          b.type = 'button';
          b.textContent = q.options[oi];
          b.addEventListener('click', function () {
            if (done) return;
            done = true;
            answered++;
            var right = oi === q.answer;
            if (right) correct++;
            buttons.forEach(function (other) {
              other.disabled = true;
              if (other.dataset.index === String(q.answer)) other.classList.add('right');
            });
            if (!right) b.classList.add('wrong');
            var why = document.createElement('p');
            why.className = 'quiz-why';
            why.innerHTML = '<b>' + (right ? 'Yes. ' : 'No. ') + '</b>';
            why.appendChild(document.createTextNode(q.why));
            box.appendChild(why);
            updateScore();
          });
          b.dataset.index = String(oi);
          buttons.push(b);
          opts.appendChild(b);
        });

        box.appendChild(opts);
        root.appendChild(box);
      });

      updateScore();
      foot.appendChild(score);
      foot.appendChild(again);
      root.appendChild(foot);
    }

    render();
  }

  global.Quiz = { mount: mount };
})(window);
