---
name: framer-motion
description: "Use when adding animations, transitions, gestures, or scroll effects to React/Next.js — Motion (formerly Framer Motion) patterns: motion.div, AnimatePresence, layout/layoutId, springs, variants, whileInView."
source: https://motion.dev/docs
generated: 2026-05-09T00:37:56.376Z
category: library
audience: creators
---

## When to use

- Animating React components declaratively with initial/animate/exit + transition props
- Orchestrating page transitions, list reorders, and shared-element layout animations
- Scroll-triggered reveals (whileInView), parallax, and pinned scroll sections
- Gesture handling — drag, hover, tap, pan — with spring physics instead of CSS keyframes

## Key concepts

### motion components

motion.div / motion.span / motion(Component) replace plain DOM nodes and accept animate, initial, exit, whileHover, whileTap, whileInView, drag, layout, and transition props. They render as the underlying element — no extra wrapper — and only opt into animation when those props are present.

### AnimatePresence

Wraps conditional renders so unmounting children can run an exit animation before they leave the tree. Only animates DIRECT children; intermediate wrappers between AnimatePresence and the conditionally-mounted node break exit animations. Each conditional child needs a stable key.

### layout / layoutId

Pass `layout` to auto-animate any size/position change a component undergoes. Pass `layoutId="shared-id"` on two components in different parts of the tree to morph between them as one unmounts and the other mounts — the foundation of shared-element transitions.

### whileInView + viewport

Scroll-triggered animation without manually wiring IntersectionObserver. Pass viewport={{ once: true }} to fire the animation only the first time the element enters; otherwise it replays on every re-entry.

### spring vs tween

Two transition types: tween is duration-based (use for choreographed reveals, page transitions); spring is physics-based via stiffness/damping/mass (use for gestures, drag release, organic motion). Default to spring for natural-feeling interaction; tween for timed sequences.

### variants + stagger

Variants are named animation states attached to a parent that propagate to children, enabling orchestrated sequences. transition.staggerChildren on the parent variant offsets each child's animation in time without per-child math.

### motion/react vs framer-motion

The package was renamed: new code should import from `motion/react` (or `motion/react-client` for Next.js client boundary). The legacy `framer-motion` import still works for back-compat but isn't where new APIs land.

## API reference

```
import { motion } from 'motion/react'
```

Preferred import path. Use 'motion/react-client' inside Next.js Server Components to mark the client boundary; 'framer-motion' still works as a legacy alias.

```
import { motion } from 'motion/react';

export function Card() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: 'spring', stiffness: 200, damping: 20 }}
    />
  );
}
```

```
AnimatePresence with conditional render
```

Wrap exits so unmounting children animate out. Each child needs a stable key. Use mode='wait' to fully unmount the previous child before mounting the next.

```
import { AnimatePresence, motion } from 'motion/react';

<AnimatePresence mode="wait">
  {open && (
    <motion.div
      key="panel"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
    />
  )}
</AnimatePresence>
```

```
Variants + staggerChildren
```

Define named states on a parent and let children inherit them. staggerChildren offsets each child's animation in sequence without manual delays.

```
const list = {
  hidden: {},
  show: { transition: { staggerChildren: 0.08 } },
};
const item = {
  hidden: { opacity: 0, y: 12 },
  show: { opacity: 1, y: 0 },
};

<motion.ul variants={list} initial="hidden" animate="show">
  {items.map((i) => (
    <motion.li key={i.id} variants={item}>{i.label}</motion.li>
  ))}
</motion.ul>
```

```
whileInView with viewport once
```

Scroll-reveal pattern. once: true prevents replay on every re-entry; amount controls how much of the element must be visible before firing.

```
<motion.section
  initial={{ opacity: 0, y: 40 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true, amount: 0.3 }}
  transition={{ duration: 0.6 }}
/>
```

```
Shared-element transition with layoutId
```

Two components with the same layoutId in different trees morph between each other as one unmounts and the other mounts.

```
// In list view
<motion.img layoutId={`hero-${id}`} src={src} />

// In detail view
<motion.img layoutId={`hero-${id}`} src={src} />
```

```
Drag + spring release
```

Gesture handling with built-in spring physics on release. dragConstraints can be a ref or numeric box.

```
<motion.div
  drag
  dragConstraints={{ top: 0, left: 0, right: 200, bottom: 200 }}
  dragTransition={{ bounceStiffness: 600, bounceDamping: 12 }}
/>
```

## Gotchas

- Package was renamed — new code should import from 'motion/react'. The 'framer-motion' import is a legacy alias and may lag behind new APIs.
- AnimatePresence only animates DIRECT children that mount/unmount. A wrapper div between AnimatePresence and the conditional node silently disables exit animations.
- Conditionally rendered children of AnimatePresence need a stable, unique key — without it, React reuses the node and exit never fires.
- layout animations require both the `layout` prop AND a layout-affecting style change (size, flex direction, grid position). Color-only changes won't trigger them.
- whileInView replays on every viewport re-entry by default. Pass viewport={{ once: true }} for marketing-style reveals.
- Animating non-transformable properties (height, width, top, left) is expensive and triggers layout. Prefer transform/scale/translate; use the `layout` prop for genuine size changes.
- In Next.js App Router, motion components are client-only — import from 'motion/react-client' or mark the file 'use client'.
- Motion 11+ requires React 18+. Reduced-motion users still get instant transitions unless you opt out with MotionConfig reducedMotion='never'.

---
Generated by SkillMake from https://motion.dev/docs on 2026-05-09T00:37:56.376Z.
Verify against source before relying on details.