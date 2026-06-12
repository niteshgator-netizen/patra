<script setup>
// patra-final 6c: line sibling of BarChart.vue — same chart.js stack the
// reports pages already ship, registered for line rendering.
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  Legend,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';

const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  chartOptions: {
    type: Object,
    default: () => ({}),
  },
});

ChartJS.register(
  Title,
  Tooltip,
  Legend,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    duration: 0,
  },
  plugins: {
    legend: {
      display: true,
      labels: {
        fontFamily,
        boxWidth: 12,
      },
    },
  },
  scales: {
    x: {
      ticks: {
        fontFamily,
      },
      grid: {
        drawOnChartArea: false,
      },
    },
    y: {
      type: 'linear',
      position: 'left',
      beginAtZero: true,
      ticks: {
        fontFamily,
      },
      grid: {
        drawOnChartArea: false,
      },
    },
  },
};

const options = computed(() => {
  return { ...defaultChartOptions, ...props.chartOptions };
});
</script>

<template>
  <Line :data="collection" :options="options" />
</template>
