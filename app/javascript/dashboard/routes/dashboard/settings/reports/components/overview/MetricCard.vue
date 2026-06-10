<script setup>
defineProps({
  header: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex flex-col m-0.5 px-6 py-5 rounded-xl flex-grow text-n-slate-12 shadow outline-1 outline outline-n-container bg-n-solid-2 min-h-[10rem]"
  >
    <div
      class="card-header grid w-full mb-6 grid-cols-[repeat(auto-fit,minmax(max-content,50%))] gap-y-2"
    >
      <slot name="header">
        <div class="flex items-center gap-2 flex-row">
          <h5 class="mb-0 text-n-slate-12 font-medium text-lg">
            {{ header }}
          </h5>
          <span
            class="flex flex-row items-center py-0.5 px-2 rounded bg-n-teal-3 text-xs"
          >
            <span
              class="bg-n-teal-9 h-1 w-1 rounded-full mr-1 rtl:mr-0 rtl:ml-0"
            />
            <span class="text-xs text-n-teal-11">
              {{ $t('OVERVIEW_REPORTS.LIVE') }}
            </span>
          </span>
        </div>
        <div class="flex flex-row items-center justify-end gap-2">
          <slot name="control" />
        </div>
      </slot>
    </div>
    <div
      v-if="!isLoading"
      class="card-body max-w-full w-full ml-auto mr-auto justify-between flex"
    >
      <slot />
    </div>
    <div v-else-if="isLoading" class="flex w-full gap-4 px-2 py-4">
      <div v-for="n in 4" :key="n" class="pat-skel h-14 flex-1" />
    </div>
  </div>
</template>
