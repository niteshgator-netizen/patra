<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const fields = ref([
  { key: 'preferred_game', label: 'Preferred Game', type: 'text' },
  { key: 'loyalty_tier', label: 'Loyalty Tier', type: 'dropdown', options: ['bronze', 'silver', 'gold', 'vip'] },
]);

const newField = ref({ key: '', label: '', type: 'text' });

const addField = () => {
  if (!newField.value.key) return;
  fields.value.push({ ...newField.value });
  newField.value = { key: '', label: '', type: 'text' };
};

const removeField = index => {
  fields.value.splice(index, 1);
};
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <h1 class="text-2xl font-semibold">{{ $t('PATRA.ATTRIBUTES.TITLE') }}</h1>
    <p class="text-sm text-n-slate-11">{{ $t('PATRA.ATTRIBUTES.SUBTITLE') }}</p>

    <div class="grid gap-2">
      <div
        v-for="(field, idx) in fields"
        :key="field.key"
        class="flex items-center justify-between p-3 border rounded-lg border-n-weak"
      >
        <div>
          <span class="font-medium">{{ field.label }}</span>
          <span class="ml-2 text-xs text-n-slate-11">({{ field.type }})</span>
        </div>
        <button class="text-xs text-n-ruby-11" @click="removeField(idx)">
          {{ $t('PATRA.ATTRIBUTES.REMOVE') }}
        </button>
      </div>
    </div>

    <div class="flex gap-2 p-3 border rounded-lg border-n-weak">
      <input v-model="newField.label" class="flex-1 p-2 text-sm border rounded-lg border-n-weak" :placeholder="$t('PATRA.ATTRIBUTES.LABEL')" />
      <select v-model="newField.type" class="p-2 text-sm border rounded-lg border-n-weak">
        <option value="text">Text</option>
        <option value="number">Number</option>
        <option value="date">Date</option>
        <option value="dropdown">Dropdown</option>
        <option value="boolean">Boolean</option>
      </select>
      <button class="px-3 py-2 text-sm text-white rounded-lg bg-n-brand" @click="addField">
        {{ $t('PATRA.ATTRIBUTES.ADD') }}
      </button>
    </div>
  </div>
</template>
