const PHONE_HEADERS = [
  'telefone',
  'telefone celular',
  'celular',
  'numero',
  'numero de telefone',
  'whatsapp',
  'whatsapp id',
  'phone',
  'phone number',
  'phone_number',
  'mobile',
];

const NAME_HEADERS = [
  'nome',
  'nome do cliente',
  'cliente',
  'contato',
  'name',
  'first name',
];

const COMPANY_HEADERS = [
  'empresa',
  'nome da empresa',
  'razao social',
  'company',
  'company name',
];

const normalizedHeader = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase();

const headerIndex = (row, aliases) =>
  row.findIndex(value => aliases.includes(normalizedHeader(value)));

const phoneScore = values =>
  values.filter(value => String(value || '').replace(/\D/g, '').length >= 10)
    .length;

export const parseDelimitedText = text => {
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;
  const source = String(text || '').replace(/^\uFEFF/, '');
  const firstLine = source.split(/\r?\n/, 1)[0] || '';
  let delimiter = ',';
  if (firstLine.includes(';')) delimiter = ';';
  else if (firstLine.includes('\t')) delimiter = '\t';

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const nextCharacter = source[index + 1];

    if (character === '"' && quoted && nextCharacter === '"') {
      value += '"';
      index += 1;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === delimiter && !quoted) {
      row.push(value.trim());
      value = '';
    } else if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && nextCharacter === '\n') index += 1;
      row.push(value.trim());
      if (row.some(cell => String(cell).trim())) rows.push(row);
      row = [];
      value = '';
    } else {
      value += character;
    }
  }

  row.push(value.trim());
  if (row.some(cell => String(cell).trim())) rows.push(row);
  return rows;
};

export const readAudienceFile = async file => {
  if (file.name.toLowerCase().endsWith('.xlsx')) {
    const { default: readXlsxFile } = await import('read-excel-file/browser');
    return readXlsxFile(file);
  }

  return parseDelimitedText(await file.text());
};

export const detectAudienceColumns = matrix => {
  const firstRow = matrix[0] || [];
  const detectedPhone = headerIndex(firstRow, PHONE_HEADERS);
  const detectedName = headerIndex(firstRow, NAME_HEADERS);
  const detectedCompany = headerIndex(firstRow, COMPANY_HEADERS);
  const hasHeader =
    detectedPhone >= 0 || detectedName >= 0 || detectedCompany >= 0;
  const dataRows = hasHeader ? matrix.slice(1) : matrix;
  const columnCount = Math.max(0, ...matrix.map(row => row.length));
  const fallbackPhone = Array.from({ length: columnCount }, (_, index) => ({
    index,
    score: phoneScore(dataRows.slice(0, 50).map(row => row[index])),
  })).sort((first, second) => second.score - first.score)[0]?.index;

  return {
    hasHeader,
    phone: detectedPhone >= 0 ? detectedPhone : (fallbackPhone ?? 0),
    name: detectedName,
    company: detectedCompany,
  };
};

export const normalizeAudiencePhone = (value, countryCode = '55') => {
  const rawValue = String(value || '').trim();
  if (!rawValue) return '';

  const explicitCountryCode =
    rawValue.startsWith('+') || rawValue.startsWith('00');
  let digits = rawValue.replace(/\D/g, '');
  if (rawValue.startsWith('00')) digits = digits.slice(2);

  if (!explicitCountryCode) {
    if (digits.startsWith('0') && [11, 12].includes(digits.length)) {
      digits = digits.slice(1);
    }
    if ([10, 11].includes(digits.length)) {
      digits = `${countryCode}${digits}`;
    }
  }

  return /^[1-9]\d{9,14}$/.test(digits) ? `+${digits}` : '';
};

export const contactsFromMatrix = (matrix, columns) => {
  const rows = columns.hasHeader ? matrix.slice(1) : matrix;
  return rows
    .filter(row => row.some(value => String(value || '').trim()))
    .map(row => ({
      phone_number: row[columns.phone],
      name: columns.name >= 0 ? row[columns.name] : '',
      company_name: columns.company >= 0 ? row[columns.company] : '',
    }));
};

export const contactsFromPastedText = text =>
  String(text || '')
    .split(/[\n,;\t]+/)
    .map(value => value.trim())
    .filter(Boolean)
    .map(phoneNumber => ({
      phone_number: phoneNumber,
      name: '',
      company_name: '',
    }));

export const buildAudiencePreview = contacts => {
  const seen = new Set();
  const valid = [];
  const invalid = [];
  let duplicates = 0;

  contacts.forEach((contact, index) => {
    const phoneNumber = normalizeAudiencePhone(contact.phone_number);
    if (!phoneNumber) {
      invalid.push({ ...contact, row: index + 1 });
      return;
    }
    if (seen.has(phoneNumber)) {
      duplicates += 1;
      return;
    }
    seen.add(phoneNumber);
    valid.push({
      phone_number: phoneNumber,
      name: String(contact.name || '').trim(),
      company_name: String(contact.company_name || '').trim(),
    });
  });

  return { valid, invalid, duplicates, total: contacts.length };
};
