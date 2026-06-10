import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import PatraAiHandoffCard from '../PatraAiHandoffCard.vue';

const buildStore = conversations =>
  createStore({
    getters: {
      getAllConversations: () => conversations,
    },
  });

const mountCard = conversations =>
  mount(PatraAiHandoffCard, {
    props: { conversationId: 1 },
    global: {
      plugins: [buildStore(conversations)],
    },
  });

describe('PatraAiHandoffCard.vue', () => {
  it('is fully hidden when the conversation has no AI attributes', () => {
    const wrapper = mountCard([
      { id: 1, labels: [], additional_attributes: {} },
    ]);
    expect(wrapper.find('.patra-ai-handoff-card, .ai-hc').exists()).toBe(false);
    expect(wrapper.text()).toBe('');
  });

  it('is hidden when the conversation is missing entirely', () => {
    const wrapper = mountCard([]);
    expect(wrapper.text()).toBe('');
  });

  it('renders intent confidence when real AI attributes exist', () => {
    const wrapper = mountCard([
      {
        id: 1,
        labels: [],
        additional_attributes: { last_intent_confidence: 0.87 },
      },
    ]);
    expect(wrapper.text()).toContain('87%');
  });

  it('renders the awaiting-amount intent label from real attributes', () => {
    const wrapper = mountCard([
      {
        id: 1,
        labels: [],
        additional_attributes: { awaiting_load_amount: true },
      },
    ]);
    expect(wrapper.text()).toContain('Load deposit — awaiting amount');
  });
});
