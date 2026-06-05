<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BulkLabelActions from 'dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue';
import Policy from 'dashboard/components/policy.vue';
import PlayerTiersAPI from 'dashboard/api/playerTiers';

const props = defineProps({
  visibleContactIds: {
    type: Array,
    default: () => [],
  },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'clearSelection',
  'assignLabels',
  'assignTier',
  'toggleAll',
  'deleteSelected',
]);

const { t } = useI18n();
const route = useRoute();
const playerTiers = ref([]);

const selectedCount = computed(() => props.selectedContactIds.length);
const totalVisibleContacts = computed(() => props.visibleContactIds.length);

const selectAllLabel = computed(() => {
  if (!totalVisibleContacts.value) {
    return '';
  }

  return t('CONTACTS_BULK_ACTIONS.SELECT_ALL', {
    count: totalVisibleContacts.value,
  });
});

const selectedCountLabel = computed(() =>
  t('CONTACTS_BULK_ACTIONS.SELECTED_COUNT', {
    count: selectedCount.value,
  })
);

const allItems = computed(() =>
  props.visibleContactIds.map(id => ({
    id,
  }))
);

const selectionModel = computed({
  get: () => new Set(props.selectedContactIds),
  set: newSet => {
    if (!props.visibleContactIds.length) {
      emit('toggleAll', false);
      return;
    }

    const shouldSelectAll = props.visibleContactIds.every(id => newSet.has(id));
    emit('toggleAll', shouldSelectAll);
  },
});

const handleAssignLabels = labels => {
  emit('assignLabels', labels);
};

const fetchTiers = async () => {
  try {
    const { data } = await PlayerTiersAPI.getPlayerTiers(route.params.accountId);
    playerTiers.value = data;
  } catch (error) {
    console.error('Failed to fetch tiers:', error);
  }
};

const handleTierChange = event => {
  const rawValue = event.target.value;
  if (!rawValue) return;

  const tierId = rawValue === 'clear' ? null : parseInt(rawValue, 10);
  emit('assignTier', tierId);
  event.target.value = '';
};

onMounted(() => {
  fetchTiers();
});
</script>

<template>
  <div
    class="sticky top-0 z-10 bg-gradient-to-b from-n-surface-1 from-90% to-transparent pt-1 pb-2"
  >
    <BulkSelectBar
      v-model="selectionModel"
      :all-items="allItems"
      :select-all-label="selectAllLabel"
      :selected-count-label="selectedCountLabel"
      class="py-2 ltr:!pr-3 rtl:!pl-3 justify-between"
    >
      <template #primaryActions>
        <Button
          sm
          ghost
          slate
          :label="t('CONTACTS_BULK_ACTIONS.CLEAR_SELECTION')"
          class="!px-1"
          @click="emit('clearSelection')"
        />
      </template>
      <template #actions>
        <div class="flex items-center gap-2 ml-auto">
          <BulkLabelActions
            type="contact"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @assign="handleAssignLabels"
          />
          <select
            class="tier-bulk-select"
            :disabled="!selectedCount || isLoading"
            @change="handleTierChange"
          >
            <option value="">
              {{ t('CONTACTS_BULK_ACTIONS.ASSIGN_TIER') }}
            </option>
            <option
              v-for="tier in playerTiers"
              :key="tier.id"
              :value="tier.id"
            >
              {{ tier.badge_text || tier.name }}
            </option>
            <option value="clear">
              {{ t('CONTACTS_BULK_ACTIONS.CLEAR_TIER') }}
            </option>
          </select>
          <div class="w-px h-3 bg-n-weak rounded-lg" />
          <Policy :permissions="['administrator']">
            <Button
              v-tooltip.bottom="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              sm
              ghost
              ruby
              icon="i-lucide-trash"
              :label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :aria-label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :disabled="!selectedCount || isLoading"
              :is-loading="isLoading"
              class="!px-2 [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
              @click="emit('deleteSelected')"
            />
          </Policy>
        </div>
      </template>
    </BulkSelectBar>
  </div>
</template>

<style scoped>
.tier-bulk-select {
  min-width: 140px;
  padding: 6px 10px;
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-6) / 1);
  background: rgb(var(--slate-2) / 1);
  color: rgb(var(--slate-12) / 1);
  font-size: 12px;
}

.tier-bulk-select:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
