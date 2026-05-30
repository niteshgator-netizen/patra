<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactNoteItem from './components/ContactNoteItem.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const state = reactive({
  message: '',
});

const currentUser = useMapGetter('getCurrentUser');
const notesByContact = useMapGetter('contactNotes/getAllNotesByContactId');
const uiFlags = useMapGetter('contactNotes/getUIFlags');
const isFetchingNotes = computed(() => uiFlags.value.isFetching);
const isCreatingNote = computed(() => uiFlags.value.isCreating);
const notes = computed(() => notesByContact.value(route.params.contactId));

const getWrittenBy = note => {
  const isCurrentUser = note?.user?.id === currentUser.value.id;
  return isCurrentUser
    ? t('CONTACTS_LAYOUT.SIDEBAR.NOTES.YOU')
    : note?.user?.name || 'Bot';
};

const onAdd = content => {
  if (!content) return;
  const { contactId } = route.params;
  store.dispatch('contactNotes/create', { content, contactId });
  state.message = '';
};

const onDelete = noteId => {
  if (!noteId) return;
  const { contactId } = route.params;
  store.dispatch('contactNotes/delete', { noteId, contactId });
};

const keyboardEvents = {
  '$mod+Enter': {
    action: () => onAdd(state.message),
    allowOnFocusedInput: true,
  },
};
useKeyboardEvents(keyboardEvents);
</script>

<template>
  <div class="notes-tab">
    <span class="add-link">{{
      t('CONTACTS_LAYOUT.SIDEBAR.NOTES.ADD_NOTE')
    }}</span>
    <Editor
      v-model="state.message"
      :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.PLACEHOLDER')"
      focus-on-mount
      class="notes-editor"
    >
      <template #actions>
        <div class="notes-actions">
          <Button
            variant="link"
            color="blue"
            size="sm"
            :label="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.SAVE')"
            :is-loading="isCreatingNote"
            :disabled="!state.message || isCreatingNote"
            @click="onAdd(state.message)"
          />
        </div>
      </template>
    </Editor>
    <div v-if="isFetchingNotes" class="tab-loading">
      <Spinner />
    </div>
    <div v-else-if="notes.length > 0" class="notes-list">
      <ContactNoteItem
        v-for="note in notes"
        :key="note.id"
        :note="note"
        :written-by="getWrittenBy(note)"
        allow-delete
        @delete="onDelete"
      />
    </div>
    <p v-else class="empty-note">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.NOTES.EMPTY_STATE') }}
    </p>
  </div>
</template>

<style scoped>
.notes-tab {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.add-link {
  font-size: 12.5px;
  color: var(--patra-3, #a78bfa);
  cursor: pointer;
  margin-bottom: 0;
  display: inline-block;
  border: none;
  background: transparent;
  padding: 0;
  text-align: left;
}

.add-link:hover {
  text-decoration: underline;
}

.tab-loading {
  display: flex;
  justify-content: center;
  padding: 24px;
}

.notes-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
</style>
