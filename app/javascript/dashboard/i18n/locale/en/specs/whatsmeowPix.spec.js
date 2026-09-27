import { describe, expect, it } from 'vitest';
import { createI18n } from 'vue-i18n';
import conversation from '../conversation.json';
import ptBrConversation from '../../pt_BR/conversation.json';

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

  it('provides every Pix label in Brazilian Portuguese', () => {
    const english = conversation.CONVERSATION.WHATSMEOW_PIX;
    const portuguese = ptBrConversation.CONVERSATION.WHATSMEOW_PIX;
    const i18n = createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: ptBrConversation },
    });

    expect(Object.keys(portuguese).sort()).toEqual(Object.keys(english).sort());
    expect(Object.keys(portuguese.KEY_TYPES).sort()).toEqual(
      Object.keys(english.KEY_TYPES).sort()
    );
    expect(Object.keys(portuguese.KEY_PLACEHOLDERS).sort()).toEqual(
      Object.keys(english.KEY_PLACEHOLDERS).sort()
    );
    expect(i18n.global.t('CONVERSATION.WHATSMEOW_PIX.COPY_KEY')).toBe(
      'Copiar chave Pix'
    );
    expect(i18n.global.t('CONVERSATION.WHATSMEOW_PIX.SEND')).toBe(
      'Enviar chave Pix'
    );
  });
});
