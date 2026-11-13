const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('lib/thereish_web/components/room_components.ex', 'utf8');
const js = source.match(/name="\.RevealSequence">\s*([\s\S]*?)<\/script>/)[1];
const adapter = new Function(js.replace('export default', 'return'))();
const rooms = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

function mount(room, {elapsed = 0, quiet = false, hidden = false, reduced = false, missing = false, splitHidden = false} = {}) {
  let clock = 0, serial = 0;
  const tasks = new Map(), animations = [], writes = [], flashes = [];
  const schedule = room.reveal_sequence;
  function timer(fn, delay, frame = false) {
    const id = ++serial;
    tasks.set(id, {fn, at: clock + delay, frame});
    return id;
  }
  global.performance = {now: () => clock};
  global.setTimeout = (fn, delay) => timer(fn, delay);
  global.clearTimeout = id => tasks.delete(id);
  global.requestAnimationFrame = fn => timer(fn, 16, true);
  global.cancelAnimationFrame = id => tasks.delete(id);
  global.window = {matchMedia: () => ({matches: reduced})};

  function node(role, target) {
    let text = target;
    return {role, dataset: {target: String(target)}, style: {},
      get textContent() {return text;},
      set textContent(value) {text = value; writes.push({at: clock, value: Number(value)});},
      remove() {this.removed = true;},
      animate(frames, timing) {
        const animation = {role, frames, timing, at: clock, currentTime: 0,
          cancel() {this.cancelled = true; this.oncancel?.();}};
        animations.push(animation);
        return animation;
      }
    };
  }
  const number = quiet || room.reveal.closeness === null ? null : node('closeness', room.reveal.closeness);
  const nodes = {
    'closeness': number,
    'closeness-display': number && node('closeness-display'),
    'band': number && node('band'),
    'ladder-rail': node('ladder-rail'),
    'rail-marker': room.reveal.closeness === null ? null : node('rail-marker', room.reveal.closeness),
    'short-by': room.reveal.gap > 0 && room.reveal.gap <= 15 ? node('short-by') : null,
    'split-reading': splitHidden || !room.reveal.split ? null : node('split-reading')
  };
  const cards = room.reveal.bridges.map(() => {
    const card = node('bridge');
    card.querySelector = () => node('bridge-name');
    return card;
  });
  const arrays = {
    '[data-bridge]': cards,
    '[data-role="call-pin"]': room.reveal.calls.map(() => node('call-pin')),
    '[data-role="rail-mark"]': room.reveal.split && !splitHidden ? [node('rail-mark'), node('rail-mark')] : []
  };
  const el = {dataset: {
    sequence: missing ? '' : JSON.stringify({...schedule, elapsed}),
    presentation: JSON.stringify({quiet, closeness: room.reveal.closeness, overruled: room.reveal['overruled?']}),
    melded: String(room.reveal['melded?'])
  }, querySelector: selector => nodes[selector.match(/data-role="(.*?)"/)[1]],
  querySelectorAll: selector => arrays[selector] || []};
  global.document = {hidden,
    createElement: () => node('meld-flash'),
    body: {appendChild: n => {flashes.push(n);}}
  };
  const hook = {...adapter, el};
  hook.mounted();
  function advance(to, frames = true) {
    while (true) {
      const next = [...tasks].filter(([,t]) => t.at <= to && (frames || !t.frame)).sort((a,b) => a[1].at - b[1].at)[0];
      if (!next) break;
      const [id, task] = next; tasks.delete(id); clock = task.at; task.fn(clock);
    }
    clock = to;
  }
  return {hook, el, number, nodes, tasks, animations, writes, flashes, advance};
}

for (const room of rooms) {
  for (const quiet of [false, true]) {
    const h = mount(room, {quiet});
    const deadline = room.reveal_sequence.duration;
    h.advance(deadline);
    if (h.number) assert.equal(Number(h.number.textContent), room.reveal.closeness);
    assert.equal(h.tasks.size, 0, 'work remains after the promised completion');
    for (const a of h.animations) {
      assert.ok(a.at + (a.timing.delay || 0) + a.timing.duration - a.currentTime <= deadline,
        `${a.role} finishes after ${deadline}`);
    }
    const count = h.animations.find(a => a.role === 'rail-marker');
    if (h.number && count) {
      assert.equal(h.writes.at(-1).at, count.timing.delay + count.timing.duration);
    }
    assert.ok(h.writes.every(w => w.at <= deadline));
    h.hook.destroyed();
    assert.ok(h.animations.every(a => a.cancelled));
  }
}

const room = rooms.find(r => r.reveal.split && r.reveal.bridges.length === 2);
const deadline = room.reveal_sequence.duration;
for (const options of [{reduced:true}, {hidden:true}, {elapsed:deadline}, {missing:true}]) {
  const h = mount(room, options);
  assert.equal(Number(h.number.textContent), room.reveal.closeness);
  assert.equal(h.tasks.size, 0);
  assert.equal(h.animations.length, 0);
}
{
  const h = mount(room, {elapsed:900});
  assert.ok(Number(h.number.textContent) > 0);
  assert.ok(h.animations.every(a => a.role !== 'bridge' && a.role !== 'bridge-name'));
  h.advance(deadline - 900);
  assert.equal(Number(h.number.textContent), room.reveal.closeness);
  assert.equal(h.tasks.size, 0);
}
{
  const h = mount(room);
  h.advance(900);
  const active = h.animations.length;
  h.number.textContent = room.reveal.closeness; // LiveView patches the rendered number.
  h.hook.updated();
  assert.equal(h.animations.length, active, 'a Reaction replayed the schedule');
  assert.ok(Number(h.number.textContent) < room.reveal.closeness);
  h.advance(1000);
  h.number.dataset.target = '95';
  h.number.textContent = '95';
  h.el.dataset.presentation = 'overruled';
  h.hook.updated();
  h.advance(5000);
  assert.equal(Number(h.number.textContent), 95, 'an old number write overwrote the Overrule');
  assert.equal(h.tasks.size, 0);
  assert.ok(h.animations.every(a => a.cancelled));
}
{
  const h = mount(room);
  h.advance(100);
  h.hook.destroyed();
  const writes = h.writes.length;
  h.advance(5000);
  assert.equal(h.writes.length, writes);
  assert.equal(h.tasks.size, 0);
}
{
  const h = mount(room);
  h.advance(deadline, false); // A throttled frame loop must still land exactly on time.
  assert.equal(Number(h.number.textContent), room.reveal.closeness);
}
{
  const h = mount(room, {splitHidden:true});
  h.advance(900);
  const count = h.animations.length;
  h.el.dataset.presentation = 'split shown';
  h.hook.updated();
  assert.equal(h.animations.length, count, 'a newly shown reading restarted the performance');
  assert.equal(Number(h.number.textContent), room.reveal.closeness);
  assert.equal(h.tasks.size, 0);
}
{
  const h = mount(room);
  h.advance(200);
  const old = [...h.animations];
  h.el.dataset.sequence = JSON.stringify({...room.reveal_sequence, id:999, elapsed:0});
  h.number.dataset.target = '17';
  h.hook.updated();
  assert.ok(old.every(a => a.cancelled));
  h.advance(200 + deadline);
  assert.equal(Number(h.number.textContent), 17, 'the previous reveal wrote into its replacement');
  assert.equal(h.tasks.size, 0);
}
{
  const meld = rooms.find(r => r.reveal['melded?']);
  const h = mount(meld);
  h.advance(1100);
  assert.equal(h.flashes.length, 1);
  h.hook.destroyed();
  assert.ok(h.flashes.every(f => f.removed));
  h.advance(5000);
  assert.equal(h.tasks.size, 0);
  const ruled = structuredClone(meld);
  ruled.reveal['overruled?'] = true;
  const reconnected = mount(ruled, {elapsed:300});
  assert.equal(reconnected.animations.length, 0, 'a reconnect replayed an Overruled performance');
}
console.log('REVEAL_TESTS_PASSED');
