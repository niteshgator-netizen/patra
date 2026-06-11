<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';
export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div
    class="patra-empty-state relative flex flex-col items-center justify-center h-full w-full overflow-hidden"
  >
    <!-- Subtle static gradient wash — no animation by design -->
    <div class="patra-empty-glow" aria-hidden="true" />
    <div class="patra-empty-mark" aria-hidden="true">P</div>
    <span
      class="relative text-sm text-n-slate-12 font-medium text-center max-w-xs"
    >
      {{ message }}
    </span>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder class="relative" />
  </div>
</template>

<style scoped>
.patra-empty-glow {
  position: absolute;
  top: 50%;
  left: 50%;
  width: 520px;
  height: 520px;
  transform: translate(-50%, -58%);
  border-radius: 50%;
  pointer-events: none;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.1) 0%,
    rgba(110, 86, 207, 0.04) 45%,
    transparent 70%
  );
}

.dark .patra-empty-glow {
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.16) 0%,
    rgba(110, 86, 207, 0.06) 45%,
    transparent 70%
  );
}

.patra-empty-mark {
  position: relative;
  width: 64px;
  height: 64px;
  margin-bottom: 20px;
  border-radius: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Space Grotesk', sans-serif;
  font-size: 32px;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  box-shadow:
    0 10px 30px rgba(110, 86, 207, 0.35),
    inset 0 1px 0 rgba(255, 255, 255, 0.22);
}
</style>
