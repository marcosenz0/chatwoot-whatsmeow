import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  formatBytes,
  fileSizeInMegaBytes,
  checkFileSizeLimit,
  resolveMaximumFileUploadSize,
  isFileTypeAllowedForChannel,
  appendWhatsAppCloudMimeAliases,
} from '../FileHelper';

describe('#File Helpers', () => {
  describe('formatBytes', () => {
    it('should return zero bytes if 0 is passed', () => {
      expect(formatBytes(0)).toBe('0 Bytes');
    });
    it('should return in bytes if 1000 is passed', () => {
      expect(formatBytes(1000)).toBe('1000 Bytes');
    });
    it('should return in KB if 100000 is passed', () => {
      expect(formatBytes(10000)).toBe('9.77 KB');
    });
    it('should return in MB if 10000000 is passed', () => {
      expect(formatBytes(10000000)).toBe('9.54 MB');
    });
  });

  describe('fileSizeInMegaBytes', () => {
    it('should return zero if 0 is passed', () => {
      expect(fileSizeInMegaBytes(0)).toBe(0);
    });
    it('should return 19.07 if 20000000 is passed', () => {
      expect(fileSizeInMegaBytes(20000000)).toBeCloseTo(19.07, 2);
    });
  });

  describe('checkFileSizeLimit', () => {
    it('should return false if file with size 62208194 and file size limit 40 are passed', () => {
      expect(checkFileSizeLimit({ file: { size: 62208194 } }, 40)).toBe(false);
    });
    it('should return true if file with size 62208194 and file size limit 40 are passed', () => {
      expect(checkFileSizeLimit({ file: { size: 199154 } }, 40)).toBe(true);
    });
  });

  describe('resolveMaximumFileUploadSize', () => {
    it('should return default when value is undefined', () => {
      expect(resolveMaximumFileUploadSize(undefined)).toBe(
        DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE
      );
    });

    it('should return default when value is not a positive number', () => {
      expect(resolveMaximumFileUploadSize('not-a-number')).toBe(
        DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE
      );
      expect(resolveMaximumFileUploadSize(-5)).toBe(
        DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE
      );
    });

    it('should parse numeric strings and numbers', () => {
      expect(resolveMaximumFileUploadSize('50')).toBe(50);
      expect(resolveMaximumFileUploadSize(75)).toBe(75);
    });
  });

  describe('isFileTypeAllowedForChannel', () => {
    describe('edge cases', () => {
      it('should return false for null file', () => {
        expect(isFileTypeAllowedForChannel(null)).toBe(false);
      });

      it('should return false for undefined file', () => {
        expect(isFileTypeAllowedForChannel(undefined)).toBe(false);
      });

      it('should return false for file with zero size', () => {
        const file = { name: 'test.png', type: 'image/png', size: 0 };
        expect(isFileTypeAllowedForChannel(file)).toBe(false);
      });
    });

    describe('wildcard MIME types', () => {
      it('should allow image/png when image/* is allowed', () => {
        const file = { name: 'test.png', type: 'image/png', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });

      it('should allow image/jpeg when image/* is allowed', () => {
        const file = { name: 'test.jpg', type: 'image/jpeg', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });

      it('should allow audio/mp3 when audio/* is allowed', () => {
        const file = { name: 'test.mp3', type: 'audio/mp3', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });

      it('should allow video/mp4 when video/* is allowed', () => {
        const file = { name: 'test.mp4', type: 'video/mp4', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });
    });

    describe('exact MIME types', () => {
      it('should allow application/pdf when explicitly allowed', () => {
        const file = { name: 'test.pdf', type: 'application/pdf', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });

      it('should allow text/plain when explicitly allowed', () => {
        const file = { name: 'test.txt', type: 'text/plain', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });
    });

    describe('file extensions', () => {
      it('should allow .3gpp extension when explicitly allowed', () => {
        const file = { name: 'test.3gpp', type: '', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(true);
      });
    });

    describe('Instagram special handling', () => {
      it('should use Instagram rules when isInstagramChannel is true', () => {
        const file = { name: 'test.png', type: 'image/png', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
            isInstagramChannel: true,
          })
        ).toBe(true);
      });

      it('should use Instagram rules when conversationType is instagram_direct_message', () => {
        const file = { name: 'test.png', type: 'image/png', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
            conversationType: 'instagram_direct_message',
          })
        ).toBe(true);
      });
    });

    describe('disallowed file types', () => {
      it('should reject executable files', () => {
        const file = {
          name: 'malware.exe',
          type: 'application/x-msdownload',
          size: 1000,
        };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(false);
      });

      it('should reject unsupported file types', () => {
        const file = {
          name: 'test.xyz',
          type: 'application/x-unknown',
          size: 1000,
        };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::WebWidget',
          })
        ).toBe(false);
      });
    });

    describe('channel-specific rules', () => {
      it('should allow WhatsApp-specific file types', () => {
        const file = { name: 'test.pdf', type: 'application/pdf', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::Whatsapp',
          })
        ).toBe(true);
      });

      it('should allow Twilio WhatsApp-specific file types', () => {
        const file = { name: 'test.pdf', type: 'application/pdf', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::TwilioSms',
            medium: 'whatsapp',
          })
        ).toBe(true);
      });

      it.each([
        ['voice.mp3', 'audio/mpeg'],
        ['voice.m4a', 'audio/mp4'],
        ['video.3gp', 'video/3gpp'],
      ])(
        'should allow official WhatsApp MIME alias %s without changing other WhatsApp inboxes',
        (name, type) => {
          const file = { name, type, size: 1000 };
          const channelOptions = { channelType: 'Channel::Whatsapp' };

          expect(
            isFileTypeAllowedForChannel(file, {
              ...channelOptions,
              isWhatsAppCloudChannel: true,
            })
          ).toBe(true);
          expect(isFileTypeAllowedForChannel(file, channelOptions)).toBe(false);
        }
      );

      it.each([
        ['voice.mp3', 'audio/mp3'],
        ['voice.m4a', 'audio/m4a'],
        ['video.3gp', 'video/3gp'],
      ])('should preserve legacy WhatsApp MIME type %s', (name, type) => {
        expect(
          isFileTypeAllowedForChannel(
            { name, type, size: 1000 },
            {
              channelType: 'Channel::Whatsapp',
              isWhatsAppCloudChannel: true,
            }
          )
        ).toBe(true);
      });
    });

    describe('private note file types', () => {
      it('should allow broader file types for private notes', () => {
        const file = {
          name: 'test.pdf',
          type: 'application/pdf',
          size: 1000,
        };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::Line',
            isOnPrivateNote: true,
          })
        ).toBe(true);
      });

      it('should allow CSV files in private notes', () => {
        const file = { name: 'data.csv', type: 'text/csv', size: 1000 };
        expect(
          isFileTypeAllowedForChannel(file, {
            channelType: 'Channel::Line',
            isOnPrivateNote: true,
          })
        ).toBe(true);
      });
    });
  });

  describe('appendWhatsAppCloudMimeAliases', () => {
    it('should append canonical aliases while retaining and deduplicating legacy types', () => {
      const allowedTypes = appendWhatsAppCloudMimeAliases(
        'audio/mp3, audio/m4a, video/3gp, audio/mpeg'
      ).split(', ');

      expect(allowedTypes).toEqual([
        'audio/mp3',
        'audio/m4a',
        'video/3gp',
        'audio/mpeg',
        'audio/mp4',
        'video/3gpp',
      ]);
    });
  });
});
