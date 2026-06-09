<script setup>
defineProps({
  isLoading: {
    type: Boolean,
    default: false,
  },
  noRecordsFound: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
  noRecordsMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 font-inter">
    <slot name="header" />
    <!-- Added to render any templates that should be rendered before body -->
    <main class="pat-settings-section">
      <slot name="preBody" />
      <slot v-if="isLoading" name="loading">
        <woot-loading-state :message="loadingMessage" />
      </slot>
      <p
        v-else-if="noRecordsFound"
        class="flex-1 py-20 flex items-center justify-center text-base text-n-slate-12"
      >
        {{ noRecordsMessage }}
      </p>
      <slot v-else name="body" />
      <!-- Do not delete the slot below. It is required to render anything that is not defined in the above slots. -->
      <slot />
    </main>
  </div>
</template>

<style scoped>
/* ── v6 settings ── */
.pat-settings-section {
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 14px;
  padding: 22px 24px;
  margin-bottom: 20px;
}

.pat-settings-section h2 {
  font-family: 'Space Grotesk', sans-serif;
  font-size: 15px;
  font-weight: 600;
  color: var(--text, #ededf2);
  margin-bottom: 16px;
}

.pat-settings-field {
  margin-bottom: 16px;
}

.pat-settings-field label {
  display: block;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-2, #a8a6b6);
  margin-bottom: 6px;
  letter-spacing: 0.01em;
}

.pat-settings-field :deep(input),
.pat-settings-field :deep(textarea),
.pat-settings-field :deep(select) {
  width: 100%;
  background: var(--canvas, #050409);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 9px 13px;
  color: var(--text, #ededf2);
  font-size: 13px;
  font-family: 'Inter', sans-serif;
  outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.pat-settings-field :deep(input:focus),
.pat-settings-field :deep(textarea:focus) {
  border-color: var(--patra, #6e56cf);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.13);
}

.pat-settings-footer {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  padding-top: 16px;
  border-top: 1px solid var(--border, #171520);
  margin-top: 16px;
}

.pat-settings-section :deep(section.border-t) {
  border-color: var(--border, #171520) !important;
}

.pat-settings-section :deep(.pat-settings-field),
.pat-settings-section :deep(.fld) {
  margin-bottom: 16px;
}

.pat-settings-section :deep(.pat-settings-field label),
.pat-settings-section :deep(.fld label) {
  display: block;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-2, #a8a6b6);
  margin-bottom: 6px;
  letter-spacing: 0.01em;
}

.pat-settings-section :deep(input:not([type='checkbox']):not([type='radio'])),
.pat-settings-section :deep(textarea),
.pat-settings-section :deep(select) {
  width: 100%;
  background: var(--canvas, #050409);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 9px 13px;
  color: var(--text, #ededf2);
  font-size: 13px;
  font-family: 'Inter', sans-serif;
  outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.pat-settings-section :deep(input:not([type='checkbox']):not([type='radio']):focus),
.pat-settings-section :deep(textarea:focus),
.pat-settings-section :deep(select:focus) {
  border-color: var(--patra, #6e56cf);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.13);
}

.pat-settings-section :deep(.pat-settings-footer),
.pat-settings-section :deep(.flex.justify-end.gap-2),
.pat-settings-section :deep(.flex.justify-end.gap-3) {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  padding-top: 16px;
  border-top: 1px solid var(--border, #171520);
  margin-top: 16px;
}
</style>
