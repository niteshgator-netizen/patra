import { mount, flushPromises } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import SuggestedReplyCard from '../SuggestedReplyCard.vue';

vi.mock('dashboard/api/patraAi', () => ({
  default: {
    copilotSuggestion: vi
      .fn()
      .mockResolvedValue({ data: { suggestion: 'hey! sending that now' } }),
  },
}));

describe('SuggestedReplyCard.vue', () => {
  it('emits the suggestion into the composer bus on Apply', async () => {
    const received = [];
    const onInsert = payload => received.push(payload);
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, onInsert);

    const wrapper = mount(SuggestedReplyCard, {
      props: { conversationId: 7 },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('hey! sending that now');

    await wrapper.find('.sr-use').trigger('click');
    expect(received).toEqual(['hey! sending that now']);
    expect(wrapper.emitted('apply')[0]).toEqual(['hey! sending that now']);

    emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, onInsert);
  });

  it('hides itself when dismissed', async () => {
    const wrapper = mount(SuggestedReplyCard, {
      props: { conversationId: 7 },
    });
    await flushPromises();

    await wrapper.find('.sr-dismiss').trigger('click');
    expect(wrapper.find('.suggested-reply-card').exists()).toBe(false);
  });
});
