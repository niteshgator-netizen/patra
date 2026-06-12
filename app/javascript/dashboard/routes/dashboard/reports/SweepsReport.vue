<script setup>
import { computed, onMounted, ref } from 'vue';
import PatraReportsAPI from 'dashboard/api/patraReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import LineChart from 'shared/components/charts/LineChart.vue';

const report = ref(null);
const loading = ref(true);
const error = ref(null);
const period = ref('week');

const fetchReport = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await PatraReportsAPI.sweeps(period.value);
    report.value = data;
  } catch (e) {
    error.value = e?.message || '';
  } finally {
    loading.value = false;
  }
};

const setPeriod = key => {
  if (period.value === key) return;
  period.value = key;
  fetchReport();
};

const csvUrl = computed(() => PatraReportsAPI.sweepsCsvUrl(period.value));

const hasData = computed(
  () =>
    (report.value?.totals?.loads_count || 0) > 0 ||
    (report.value?.totals?.cashouts_count || 0) > 0
);

const money = value => `$${Number(value || 0).toFixed(2)}`;

// patra-final 6c (G10): per-game weekly loads/cashouts line charts. Data is
// the fixed 8-week game_trend block from the sweeps payload.
const weekLabel = iso => {
  const date = new Date(`${iso}T00:00:00`);
  return `${date.getMonth() + 1}/${date.getDate()}`;
};

const gameTrends = computed(() =>
  (report.value?.game_trend || []).map(game => ({
    game: game.game,
    collection: {
      labels: game.weeks.map(week => weekLabel(week.week)),
      datasets: [
        {
          label: 'Loads',
          data: game.weeks.map(week => week.loads),
          borderColor: '#3fb950',
          backgroundColor: '#3fb950',
          tension: 0.3,
          pointRadius: 2,
        },
        {
          label: 'Cashouts',
          data: game.weeks.map(week => week.cashouts),
          borderColor: '#f85149',
          backgroundColor: '#f85149',
          tension: 0.3,
          pointRadius: 2,
        },
      ],
    },
  }))
);

onMounted(fetchReport);
</script>

<template>
  <div class="flex flex-col gap-4 p-6 sw-page">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12 sw-display">
          {{ $t('PATRA.SWEEPS.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">{{ $t('PATRA.SWEEPS.SUBTITLE') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <div class="sw-period">
          <button
            type="button"
            class="sw-period-btn"
            :class="{ active: period === 'day' }"
            @click="setPeriod('day')"
          >
            {{ $t('PATRA.SWEEPS.DAILY') }}
          </button>
          <button
            type="button"
            class="sw-period-btn"
            :class="{ active: period === 'week' }"
            @click="setPeriod('week')"
          >
            {{ $t('PATRA.SWEEPS.WEEKLY') }}
          </button>
        </div>
        <a :href="csvUrl" class="sw-export">
          {{ $t('PATRA.SWEEPS.EXPORT_CSV') }}
        </a>
      </div>
    </header>

    <div v-if="loading" class="flex justify-center py-16"><Spinner /></div>
    <p v-else-if="error" class="text-n-ruby-11">
      {{ $t('PATRA.SWEEPS.ERROR') }}
    </p>

    <template v-else-if="report">
      <section class="sw-kpis">
        <div class="sw-kpi">
          <div class="sw-kpi-n sw-pos">{{ money(report.totals.loads_total) }}</div>
          <div class="sw-kpi-l">
            {{ $t('PATRA.SWEEPS.LOADS') }} ({{ report.totals.loads_count }})
          </div>
        </div>
        <div class="sw-kpi">
          <div class="sw-kpi-n sw-neg">
            {{ money(report.totals.cashouts_total) }}
          </div>
          <div class="sw-kpi-l">
            {{ $t('PATRA.SWEEPS.CASHOUTS') }} ({{
              report.totals.cashouts_count
            }})
          </div>
        </div>
        <div class="sw-kpi">
          <div
            class="sw-kpi-n"
            :class="report.totals.net >= 0 ? 'sw-pos' : 'sw-neg'"
          >
            {{ money(report.totals.net) }}
          </div>
          <div class="sw-kpi-l">{{ $t('PATRA.SWEEPS.NET') }}</div>
        </div>
        <div class="sw-kpi">
          <div class="sw-kpi-n">
            {{ money(report.totals.freeplay_loads_total) }}
          </div>
          <div class="sw-kpi-l">
            {{ $t('PATRA.SWEEPS.FREEPLAY') }} ({{
              report.totals.freeplay_loads_count
            }})
          </div>
        </div>
        <div class="sw-kpi">
          <div class="sw-kpi-n">{{ money(report.totals.paid_loads_total) }}</div>
          <div class="sw-kpi-l">
            {{ $t('PATRA.SWEEPS.PAID') }} ({{ report.totals.paid_loads_count }})
          </div>
        </div>
      </section>

      <p v-if="!hasData" class="py-8 text-center text-n-slate-11">
        {{ $t('PATRA.SWEEPS.EMPTY') }}
      </p>

      <template v-else>
        <section class="sw-card">
          <h2 class="sw-card-t">{{ $t('PATRA.SWEEPS.BY_GAME') }}</h2>
          <table class="sw-table">
            <thead>
              <tr>
                <th>{{ $t('PATRA.SWEEPS.GAME') }}</th>
                <th>{{ $t('PATRA.SWEEPS.LOADS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.CASHOUTS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.NET') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in report.by_game" :key="row.game">
                <td>{{ row.game }}</td>
                <td>{{ money(row.loads_total) }} ({{ row.loads_count }})</td>
                <td>
                  {{ money(row.cashouts_total) }} ({{ row.cashouts_count }})
                </td>
                <td :class="row.net >= 0 ? 'sw-pos' : 'sw-neg'">
                  {{ money(row.net) }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="sw-card">
          <h2 class="sw-card-t">{{ $t('PATRA.SWEEPS.BY_AGENT') }}</h2>
          <p class="sw-note">{{ $t('PATRA.SWEEPS.AGENT_NOTE') }}</p>
          <table class="sw-table">
            <thead>
              <tr>
                <th>{{ $t('PATRA.SWEEPS.AGENT') }}</th>
                <th>{{ $t('PATRA.SWEEPS.LOADS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.CASHOUTS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.NET') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in report.by_agent" :key="row.agent_id">
                <td>{{ row.agent }}</td>
                <td>{{ money(row.loads_total) }} ({{ row.loads_count }})</td>
                <td>
                  {{ money(row.cashouts_total) }} ({{ row.cashouts_count }})
                </td>
                <td :class="row.net >= 0 ? 'sw-pos' : 'sw-neg'">
                  {{ money(row.net) }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section v-if="gameTrends.length" class="sw-card">
          <h2 class="sw-card-t">{{ $t('PATRA.SWEEPS.TREND_TITLE') }}</h2>
          <p class="sw-note">{{ $t('PATRA.SWEEPS.TREND_NOTE') }}</p>
          <div class="sw-trends">
            <div
              v-for="trend in gameTrends"
              :key="trend.game"
              class="sw-trend"
            >
              <h3 class="sw-trend-t">{{ trend.game }}</h3>
              <div class="sw-trend-chart">
                <LineChart :collection="trend.collection" />
              </div>
            </div>
          </div>
        </section>

        <section class="sw-card">
          <h2 class="sw-card-t">{{ $t('PATRA.SWEEPS.BY_DAY') }}</h2>
          <table class="sw-table">
            <thead>
              <tr>
                <th>{{ $t('PATRA.SWEEPS.DATE') }}</th>
                <th>{{ $t('PATRA.SWEEPS.LOADS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.CASHOUTS') }}</th>
                <th>{{ $t('PATRA.SWEEPS.NET') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in report.by_day" :key="row.date">
                <td>{{ row.date }}</td>
                <td>{{ money(row.loads_total) }} ({{ row.loads_count }})</td>
                <td>
                  {{ money(row.cashouts_total) }} ({{ row.cashouts_count }})
                </td>
                <td :class="row.net >= 0 ? 'sw-pos' : 'sw-neg'">
                  {{ money(row.net) }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </template>
    </template>
  </div>
</template>

<style scoped>
.sw-page {
  color: var(--text, #1a1a24);
}

.sw-display {
  font-family: 'Space Grotesk', 'Inter', sans-serif;
  letter-spacing: -0.01em;
}

.sw-period {
  display: flex;
  gap: 6px;
}

.sw-period-btn {
  padding: 5px 12px;
  border-radius: 8px;
  border: 1px solid var(--border, #e5e3eb);
  background: var(--surface, #fff);
  color: var(--text-3, #75727f);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.sw-period-btn.active {
  background: var(--patra, #6e56cf);
  border-color: var(--patra, #6e56cf);
  color: #fff;
}

.sw-export {
  padding: 5px 12px;
  border-radius: 8px;
  border: 1px solid var(--patra, #6e56cf);
  color: var(--patra, #6e56cf);
  font-size: 12px;
  font-weight: 600;
  text-decoration: none;
}

.sw-export:hover {
  background: rgba(110, 86, 207, 0.08);
}

.sw-kpis {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 12px;
}

.sw-kpi {
  background: var(--surface, #fff);
  border: 1px solid var(--border, #e5e3eb);
  border-radius: 14px;
  padding: 14px 16px;
}

.sw-kpi-n {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
  font-size: 22px;
  letter-spacing: -0.02em;
}

.sw-kpi-l {
  font-size: 12px;
  color: var(--text-3, #75727f);
  margin-top: 4px;
}

.sw-card {
  background: var(--surface, #fff);
  border: 1px solid var(--border, #e5e3eb);
  border-radius: 14px;
  padding: 16px;
}

.sw-card-t {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 15px;
  margin-bottom: 10px;
}

.sw-note {
  font-size: 12px;
  color: var(--text-3, #75727f);
  margin-bottom: 8px;
}

.sw-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.sw-table th {
  text-align: left;
  color: var(--text-3, #75727f);
  font-weight: 600;
  font-size: 12px;
  padding: 6px 8px;
  border-bottom: 1px solid var(--border, #e5e3eb);
}

.sw-table td {
  padding: 6px 8px;
  border-bottom: 1px solid var(--border, #e5e3eb);
}

.sw-trends {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}

.sw-trend-t {
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 6px;
}

.sw-trend-chart {
  height: 180px;
}

.sw-pos {
  color: var(--green, #1a7f37);
}

.sw-neg {
  color: var(--red, #cf222e);
}
</style>
