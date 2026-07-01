import {
  linkifyWhatsmeowPhoneNumbers,
  normalizeWhatsmeowPhoneNumber,
  whatsmeowPhoneParts,
} from '../whatsmeowPhoneNumberHelper';

describe('#normalizeWhatsmeowPhoneNumber', () => {
  it('normalizes Brazilian DDD numbers without country code', () => {
    expect(normalizeWhatsmeowPhoneNumber('63 9118-9840')).toBe('+556391189840');
    expect(normalizeWhatsmeowPhoneNumber('6391189840')).toBe('+556391189840');
  });

  it('keeps explicit E.164 numbers', () => {
    expect(normalizeWhatsmeowPhoneNumber('+556391189840')).toBe(
      '+556391189840'
    );
    expect(normalizeWhatsmeowPhoneNumber('556391189840')).toBe('+556391189840');
  });
});

describe('#whatsmeowPhoneParts', () => {
  it('detects formatted and compact phone numbers from text', () => {
    const parts = whatsmeowPhoneParts(
      'Chama no meu outro numero 63 9118-9840 ou 556391189840'
    ).filter(part => part.type === 'phone');

    expect(parts).toHaveLength(2);
    expect(parts.map(part => part.normalizedValue)).toEqual([
      '+556391189840',
      '+556391189840',
    ]);
  });

  it('ignores values shorter than six digits', () => {
    expect(whatsmeowPhoneParts('senha 12345')).toEqual([
      { type: 'text', value: 'senha 12345' },
    ]);
  });
});

describe('#linkifyWhatsmeowPhoneNumbers', () => {
  it('adds clickable phone metadata to text nodes', () => {
    const html = linkifyWhatsmeowPhoneNumbers(
      '<p>Chama no meu outro numero 63 9118-9840</p>'
    );

    expect(html).toContain('data-whatsmeow-phone-number="63 9118-9840"');
    expect(html).toContain('data-whatsmeow-phone-normalized="+556391189840"');
  });

  it('does not rewrite existing links', () => {
    const html = linkifyWhatsmeowPhoneNumbers(
      '<p><a href="tel:+556391189840">+556391189840</a></p>'
    );

    expect(html).not.toContain('data-whatsmeow-phone-number');
  });
});
