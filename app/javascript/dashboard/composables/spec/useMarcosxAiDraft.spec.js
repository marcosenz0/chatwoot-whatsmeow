import { effectScope, nextTick, ref } from 'vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import { useMarcosxAiDraft } from '../useMarcosxAiDraft';

const chat = ref({ id: 92 });
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => chat }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: { generateDraft: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('MarcoXIA composer draft', () => {
  let scope;
  let draft;
  beforeEach(() => {
    chat.value = { id: 92 };
    scope = effectScope();
    draft = scope.run(useMarcosxAiDraft);
    MarcosxAiAPI.generateDraft.mockResolvedValue({
      data: { content: 'Review this reply' },
    });
  });
  afterEach(() => scope.stop());

  it('generates through MarcoXIA and applies the suggestion only when accepted', async () => {
    await draft.execute('reply_suggestion');
    expect(MarcosxAiAPI.generateDraft).toHaveBeenCalledWith(
      92,
      {
        action: 'reply_suggestion',
        content: undefined,
        instruction: undefined,
      },
      { signal: expect.any(AbortSignal) }
    );
    expect(draft.generatedContent.value).toBe('Review this reply');
    draft.setContentReady();
    expect(draft.isButtonDisabled.value).toBe(false);
    expect(draft.accept()).toBe('Review this reply');
    expect(draft.isActive.value).toBe(false);
  });

  it('discards a late response after changing conversations', async () => {
    let resolve;
    MarcosxAiAPI.generateDraft.mockImplementation(
      () =>
        new Promise(r => {
          resolve = r;
        })
    );
    const request = draft.execute('reply_suggestion');
    chat.value = { id: 93 };
    await nextTick();
    resolve({ data: { content: 'Wrong contact' } });
    await request;
    expect(draft.generatedContent.value).toBe('');
    expect(draft.isActive.value).toBe(false);
  });

  it('refines the current draft through the same endpoint', async () => {
    await draft.execute('reply_suggestion');
    await draft.sendFollowUp('Make it shorter');
    expect(MarcosxAiAPI.generateDraft).toHaveBeenLastCalledWith(
      92,
      {
        action: 'refine',
        content: 'Review this reply',
        instruction: 'Make it shorter',
      },
      { signal: expect.any(AbortSignal) }
    );
  });
});
