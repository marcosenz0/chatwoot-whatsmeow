import {
  linkifyWhatsmeowGroupInvites,
  whatsmeowGroupInviteCode,
  whatsmeowGroupInviteParts,
  whatsmeowGroupInviteUrl,
} from '../whatsmeowGroupInviteHelper';

describe('#whatsmeowGroupInviteCode', () => {
  it('extracts the invite code from WhatsApp group links', () => {
    expect(
      whatsmeowGroupInviteCode(
        'https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ?mode=gi_t'
      )
    ).toBe('FkLadnTzxGo9S25GLHuWiZ');
    expect(
      whatsmeowGroupInviteCode(
        'chat.whatsapp.com/invite/FkLadnTzxGo9S25GLHuWiZ'
      )
    ).toBe('FkLadnTzxGo9S25GLHuWiZ');
  });

  it('rejects non WhatsApp invite URLs', () => {
    expect(whatsmeowGroupInviteCode('https://example.com/group')).toBe('');
    expect(whatsmeowGroupInviteCode('chat.whatsapp.com/a')).toBe('');
  });
});

describe('#whatsmeowGroupInviteUrl', () => {
  it('normalizes links to the canonical WhatsApp invite URL', () => {
    expect(
      whatsmeowGroupInviteUrl(
        'http://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ?mode=gi_t'
      )
    ).toBe('https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ');
  });
});

describe('#whatsmeowGroupInviteParts', () => {
  it('detects group invites in plain text', () => {
    const parts = whatsmeowGroupInviteParts(
      'Entra aqui chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ'
    );

    expect(parts).toEqual([
      { type: 'text', value: 'Entra aqui ' },
      {
        type: 'group_invite',
        value: 'chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ',
        code: 'FkLadnTzxGo9S25GLHuWiZ',
        url: 'https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ',
      },
    ]);
  });
});

describe('#linkifyWhatsmeowGroupInvites', () => {
  it('adds invite metadata to existing links', () => {
    const html = linkifyWhatsmeowGroupInvites(
      '<p><a href="https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ?mode=gi_t">group</a></p>'
    );

    expect(html).toContain(
      'data-whatsmeow-group-invite-code="FkLadnTzxGo9S25GLHuWiZ"'
    );
    expect(html).toContain(
      'data-whatsmeow-group-invite-url="https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ"'
    );
  });

  it('wraps bare invite links in clickable anchors', () => {
    const html = linkifyWhatsmeowGroupInvites(
      '<p>chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ</p>'
    );

    expect(html).toContain('<a');
    expect(html).toContain('role="button"');
    expect(html).toContain(
      'data-whatsmeow-group-invite-code="FkLadnTzxGo9S25GLHuWiZ"'
    );
  });
});
