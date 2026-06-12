<script setup>
import { ref, onMounted } from 'vue';
import PatraAuditLogsAPI from 'dashboard/api/patraAuditLogs';

const logs = ref([]);
const loading = ref(true);
const loadError = ref(false);

onMounted(async () => {
  try {
    const res = await PatraAuditLogsAPI.list();
    logs.value = res.data || [];
  } catch {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
});

const formatTime = value => {
  if (!value) return '—';
  return new Date(value).toLocaleString();
};

const formatMetadata = metadata => {
  if (!metadata || Object.keys(metadata).length === 0) return '—';
  return Object.entries(metadata)
    .map(([key, value]) => `${key}: ${value}`)
    .join(', ');
};
</script>

<template>
  <div class="flex flex-col gap-6 p-6 overflow-y-auto w-full">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">Audit Logs</h2>
      <p class="text-sm text-n-slate-11">
        Who changed what in this account — the last 100 recorded actions,
        newest first.
      </p>
    </header>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading…</div>

    <p
      v-else-if="loadError"
      class="rounded-xl border border-n-weak bg-n-solid-1 py-12 text-center text-sm text-n-slate-11"
    >
      Couldn't load audit logs. Refresh to try again.
    </p>

    <p
      v-else-if="logs.length === 0"
      class="rounded-xl border border-n-weak bg-n-solid-1 py-12 text-center text-sm text-n-slate-11"
    >
      No audit entries yet. Actions like settings changes will show up here.
    </p>

    <section v-else class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th class="pb-2 font-medium">When</th>
            <th class="pb-2 font-medium">Action</th>
            <th class="pb-2 font-medium">Target</th>
            <th class="pb-2 font-medium">Details</th>
            <th class="pb-2 font-medium">IP</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="log in logs"
            :key="log.id"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="py-2 whitespace-nowrap text-n-slate-11">
              {{ formatTime(log.created_at) }}
            </td>
            <td class="py-2 font-medium">{{ log.action }}</td>
            <td class="py-2 text-n-slate-11">
              {{ log.target_type ? `${log.target_type} #${log.target_id}` : '—' }}
            </td>
            <td class="py-2 text-n-slate-11 break-all">
              {{ formatMetadata(log.metadata) }}
            </td>
            <td class="py-2 text-n-slate-11">{{ log.ip_address || '—' }}</td>
          </tr>
        </tbody>
      </table>
    </section>
  </div>
</template>
