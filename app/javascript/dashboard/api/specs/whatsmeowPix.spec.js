import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import whatsmeowPixAPI from '../whatsmeowPix';

describe('Whatsmeow Pix API', () => {
  const originalAxios = window.axios;
  const originalPathname = window.location.pathname;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    window.history.pushState({}, '', '/app/accounts/2/conversations/42');
  });

  afterEach(() => {
    window.axios = originalAxios;
    window.history.pushState({}, '', originalPathname);
    vi.clearAllMocks();
  });

  it('loads the inbox configuration in the context of the current conversation', () => {
    whatsmeowPixAPI.getConfiguration(8, 42);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/2/inboxes/8/whatsmeow_pix',
      { params: { conversation_id: 42 } }
    );
  });

  it('updates and clears the inbox configuration', () => {
    const pix = {
      key_type: 'EMAIL',
      key: 'payments@example.com',
      merchant_name: 'Example Store',
    };

    whatsmeowPixAPI.saveConfiguration(8, pix);
    whatsmeowPixAPI.deleteConfiguration(8);

    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/2/inboxes/8/whatsmeow_pix',
      pix
    );
    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/2/inboxes/8/whatsmeow_pix'
    );
  });

  it('sends an empty body to use the configured key', () => {
    whatsmeowPixAPI.send(42);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/2/conversations/42/messages/pix',
      {}
    );
  });
});
