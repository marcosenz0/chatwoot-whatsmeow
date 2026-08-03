import {
  buildAudiencePreview,
  contactsFromMatrix,
  contactsFromPastedText,
  detectAudienceColumns,
  normalizeAudiencePhone,
  parseDelimitedText,
} from '../audienceImportUtils';

describe('WhatsApp Cloud audience import utilities', () => {
  it('parses semicolon-delimited CSV with quoted values', () => {
    expect(
      parseDelimitedText(
        'Nome;Telefone;Empresa\n"Maria; Souza";(63) 99999-1111;Acme'
      )
    ).toEqual([
      ['Nome', 'Telefone', 'Empresa'],
      ['Maria; Souza', '(63) 99999-1111', 'Acme'],
    ]);
  });

  it('detects Portuguese columns and maps spreadsheet rows', () => {
    const matrix = [
      ['Empresa', 'Nome do cliente', 'WhatsApp'],
      ['Acme', 'Maria', '63999991111'],
    ];
    const columns = detectAudienceColumns(matrix);

    expect(columns).toEqual({
      hasHeader: true,
      phone: 2,
      name: 1,
      company: 0,
    });
    expect(contactsFromMatrix(matrix, columns)).toEqual([
      {
        phone_number: '63999991111',
        name: 'Maria',
        company_name: 'Acme',
      },
    ]);
  });

  it('normalizes Brazilian numbers without using AI', () => {
    expect(normalizeAudiencePhone('(63) 99999-1111')).toBe('+5563999991111');
    expect(normalizeAudiencePhone('+1 202-555-0123')).toBe('+12025550123');
    expect(normalizeAudiencePhone('123')).toBe('');
  });

  it('deduplicates pasted numbers and reports invalid rows', () => {
    const contacts = contactsFromPastedText(
      '63999991111\n+55 63 99999-1111\nnumero-invalido'
    );
    const preview = buildAudiencePreview(contacts);

    expect(preview.valid).toHaveLength(1);
    expect(preview.duplicates).toBe(1);
    expect(preview.invalid).toHaveLength(1);
    expect(preview.total).toBe(3);
  });
});
