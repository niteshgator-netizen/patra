<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BroadcastsAPI from 'dashboard/api/broadcasts';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const loading = ref(true);
const broadcasts = ref([]);

const load = async () => {
  const { data } = await BroadcastsAPI.get();
  broadcasts.value = data;
  loading.value = false;
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <header class="flex items-center justify-between">
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ $t('PATRA.BROADCASTS.TITLE') }}
      </h1>
      <router-link
        :to="{ name: 'patra_broadcast_compose' }"
        class="px-3 py-2 text-sm text-white rounded-lg bg-n-brand"
      >
        {{ $t('PATRA.BROADCASTS.NEW') }}
      </router-link>
    </header>

    <Spinner v-if="loading" />
    <div v-else class="grid gap-3">
      <div
        v-for="b in broadcasts"
        :key="b.id"
        class="flex items-center justify-between p-4 border rounded-xl border-n-weak"
      >
        <div>
          <h3 class="font-medium">{{ b.name }}</h3>
          <p class="text-xs text-n-slate-11">
            {{ b.channel }} · {{ b.status }} · {{ b.sent_count }} sent
          </p>
        </div>
        <router-link
          :to="{ name: 'patra_broadcast_compose', params: { broadcastId: b.id } }"
          class="text-sm text-n-brand"
        >
          {{ $t('PATRA.BROADCASTS.EDIT') }}
        </router-link>
      </div>
    </div>
  </div>
</template>
