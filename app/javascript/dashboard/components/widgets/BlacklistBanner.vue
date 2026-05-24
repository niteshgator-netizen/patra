<script setup>
import { computed } from 'vue';

const props = defineProps({
  contact: {
    type: Object,
    default: null,
  },
});

const isBlacklisted = computed(() => {
  const attrs = props.contact?.custom_attributes || {};
  return attrs.blacklisted === true || attrs.blacklisted === 'true';
});

const reason = computed(() => {
  const attrs = props.contact?.custom_attributes || {};
  return attrs.blacklist_reason || '';
});
</script>

<template>
  <div
    v-if="isBlacklisted"
    class="border-b border-n-ruby-9 bg-n-ruby-9/10 px-4 py-2 text-center text-sm font-medium text-n-ruby-11"
  >
    ⚠️ {{ $t('BLACKLIST.BANNER', { reason: reason || $t('BLACKLIST.NO_REASON') }) }}
  </div>
</template>
