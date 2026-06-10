import { mount } from '@vue/test-utils';

// pat-skel is a CSS-only shimmer primitive (patra-themes.css). The contract
// components rely on: a div with the class renders, accepts sizing utilities,
// and holds no text content (it must never show raw "Loading..." strings).
const SkelRow = {
  template: '<div class="pat-skel h-10 w-full" data-test-id="skel" />',
};

describe('pat-skel loading primitive', () => {
  it('renders an empty, sized skeleton element', () => {
    const wrapper = mount(SkelRow);
    const el = wrapper.find('[data-test-id="skel"]');
    expect(el.exists()).toBe(true);
    expect(el.classes()).toContain('pat-skel');
    expect(el.classes()).toContain('h-10');
    expect(el.text()).toBe('');
  });
});
