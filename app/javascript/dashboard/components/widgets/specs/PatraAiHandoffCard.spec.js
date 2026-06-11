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
  // H1 wiring superseded C1: the card now always renders for a loaded
  // conversation so the on-demand Analyze action is reachable — but with no
  // AI attributes it shows only the header + action buttons, no data rows.
  it('shows only the header and actions when the conversation has no AI attributes', () => {
    const wrapper = mountCard([
      { id: 1, labels: [], additional_attributes: {} },
    ]);
    expect(wrapper.find('.ai-handoff-card').exists()).toBe(true);
    expect(wrapper.find('.ai-hc-analyze-btn').exists()).toBe(true);
    expect(wrapper.find('.ai-hc-intent').exists()).toBe(false);
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
