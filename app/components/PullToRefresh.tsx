'use client';

import { useEffect, useRef, type ReactNode } from 'react';

const THRESHOLD = 72; // px of (rubber-banded) pull that commits a refresh
const HOLD = 56; // where the content rests while refreshing
const SLOP = 10; // movement before we commit to a vertical pull

// Progressive resistance past the edge (Apple's rubber-band curve).
function rubberband(overshoot: number, dimension: number, c = 0.55) {
  return (overshoot * dimension * c) / (dimension + c * Math.abs(overshoot));
}

// Critically damped spring (damping 1.0) that starts from the live value and
// carries the release velocity, so a pull can be grabbed again mid-flight.
function springTo(from: number, to: number, velocity: number, response: number, onFrame: (v: number) => void) {
  const omega = (2 * Math.PI) / response;
  let x = from - to;
  let v = velocity;
  let last = performance.now();
  let raf = 0;
  const step = (now: number) => {
    const dt = Math.min((now - last) / 1000, 1 / 30);
    last = now;
    const a = -omega * omega * x - 2 * omega * v;
    v += a * dt;
    x += v * dt;
    if (Math.abs(x) < 0.3 && Math.abs(v) < 5) {
      onFrame(to);
      return;
    }
    onFrame(to + x);
    raf = requestAnimationFrame(step);
  };
  raf = requestAnimationFrame(step);
  return () => cancelAnimationFrame(raf);
}

export function PullToRefresh({
  refreshing,
  onRefresh,
  children,
}: {
  refreshing: boolean;
  onRefresh: () => void;
  children: ReactNode;
}) {
  const content = useRef<HTMLDivElement>(null);
  const indicator = useRef<HTMLDivElement>(null);
  const offset = useRef(0);
  const cancelSpring = useRef<() => void>(() => {});
  const refreshingRef = useRef(refreshing);
  const onRefreshRef = useRef(onRefresh);
  onRefreshRef.current = onRefresh;

  const render = (y: number) => {
    offset.current = y;
    if (content.current) content.current.style.transform = `translate3d(0, ${y}px, 0)`;
    if (indicator.current) {
      const p = Math.min(y / THRESHOLD, 1);
      indicator.current.style.opacity = String(p);
      // Hint in the direction of the gesture: the spinner rotates as you pull.
      indicator.current.style.transform = `translate3d(0, ${y / 2 - 14}px, 0) rotate(${p * 270}deg) scale(${0.6 + 0.4 * p})`;
    }
  };

  const settle = (to: number, velocity = 0) => {
    cancelSpring.current();
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) return render(to);
    cancelSpring.current = springTo(offset.current, to, velocity, 0.4, render);
  };

  useEffect(() => {
    refreshingRef.current = refreshing;
    indicator.current?.classList.toggle('spinning', refreshing);
    if (!refreshing) settle(0);
    else if (offset.current < HOLD) settle(HOLD); // refresh started from the button
  }, [refreshing]);

  useEffect(() => {
    const el = content.current!;
    let startY = 0;
    let base = 0;
    let tracking = false;
    let pulling = false;
    let history: { y: number; t: number }[] = [];

    const down = (e: PointerEvent) => {
      if (window.scrollY > 0 || e.button !== 0) return;
      cancelSpring.current(); // grab it mid-flight, from where it is now
      tracking = true;
      pulling = false;
      startY = e.clientY;
      base = offset.current;
      history = [{ y: e.clientY, t: e.timeStamp }];
    };

    const move = (e: PointerEvent) => {
      if (!tracking) return;
      const dy = e.clientY - startY;
      if (!pulling) {
        if (dy < -SLOP) return void (tracking = false); // it's a scroll up, let it go
        if (dy < SLOP && base === 0) return;
        pulling = true;
        el.setPointerCapture(e.pointerId);
      }
      history.push({ y: e.clientY, t: e.timeStamp });
      if (history.length > 5) history.shift();
      const raw = Math.max(0, base + dy);
      render(rubberband(raw, window.innerHeight));
    };

    const up = () => {
      if (!tracking) return;
      tracking = false;
      if (!pulling) return;
      const first = history[0];
      const last = history[history.length - 1];
      const velocity = last.t > first.t ? ((last.y - first.y) / (last.t - first.t)) * 1000 : 0;
      if (offset.current >= THRESHOLD && !refreshingRef.current) {
        navigator.vibrate?.(10);
        onRefreshRef.current();
        settle(HOLD, velocity * 0.3);
      } else {
        settle(refreshingRef.current ? HOLD : 0, velocity * 0.3);
      }
    };

    // At the top, the browser keeps upward finger swipes (scrolling) and we take
    // the downward pull; anywhere else the browser scrolls normally.
    const syncTouchAction = () => (el.style.touchAction = window.scrollY > 0 ? 'pan-y' : 'pan-x pan-down');
    syncTouchAction();
    window.addEventListener('scroll', syncTouchAction, { passive: true });

    el.addEventListener('pointerdown', down);
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    return () => {
      window.removeEventListener('scroll', syncTouchAction);
      el.removeEventListener('pointerdown', down);
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      el.removeEventListener('pointercancel', up);
      cancelSpring.current();
    };
  }, []);

  return (
    <div className="ptr">
      <div ref={indicator} className="ptr-indicator" aria-hidden>
        <svg viewBox="0 0 24 24" width="22" height="22">
          <path d="M12 3a9 9 0 1 0 9 9" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
        </svg>
      </div>
      <div ref={content} className="ptr-content">
        {children}
      </div>
    </div>
  );
}
