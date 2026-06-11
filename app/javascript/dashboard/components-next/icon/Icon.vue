<script>
import { cloneVNode, h, isVNode } from 'vue';

// Renders string icons (unocss class names), vnode icons, and component
// icons. Implemented as an options render() — NOT a functional component via
// <component :is> — so attr-only updates (e.g. a parent toggling
// `animate-spin`) re-render correctly; a child functional component with no
// props would bail out of updates and freeze its attrs after first render.
export default {
  name: 'NextIcon',
  inheritAttrs: false,
  props: {
    icon: { type: [String, Object, Function], required: true },
  },
  render() {
    if (!this.icon) return null;
    if (isVNode(this.icon)) {
      // Clone instead of returning the shared vnode: callers build these in
      // computeds and reuse them across renders, and a reused vnode drops
      // the fallthrough attrs (size/color classes) — icons render blank.
      return cloneVNode(this.icon, this.$attrs);
    }
    if (typeof this.icon === 'function') {
      return h(this.icon, this.$attrs);
    }
    return h('span', { ...this.$attrs, class: [this.icon, this.$attrs.class] });
  },
};
</script>
