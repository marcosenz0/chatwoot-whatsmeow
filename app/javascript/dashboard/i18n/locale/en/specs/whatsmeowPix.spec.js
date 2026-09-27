import { describe, expect, it } from 'vitest';
import { createI18n } from 'vue-i18n';
import conversation from '../conversation.json';

describe('Whatsmeow Pix translations', () => {
  it('renders the email placeholder without linked-message syntax errors', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: conversation },
    });

    expect(
      i18n.global.t('CONVERSATION.WHATSMEOW_PIX.KEY_PLACEHOLDERS.EMAIL')
    ).toBe('Email address');
  });

  it('has a label for editing the saved configuration', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: conversation },
    });

    expect(i18n.global.t('CONVERSATION.WHATSMEOW_PIX.EDIT_CONFIGURATION')).toBe(
      'Edit configuration'
    );
  });
});
