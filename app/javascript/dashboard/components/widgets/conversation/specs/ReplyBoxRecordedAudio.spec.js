import ReplyBox from '../ReplyBox.vue';

describe('ReplyBox recorded audio payload', () => {
  it('marks a selected Whatsmeow audio file as recorded audio', () => {
    const context = {
      attachedFiles: [
        {
          blobSignedId: 'signed-audio-blob',
          sendAsRecordedAudio: true,
        },
      ],
      currentChat: { id: 81 },
      globalConfig: { directUploadsEnabled: true },
      isAWhatsmeowChannel: true,
      isAWhatsAppCloudChannel: false,
      isAnInstagramChannel: false,
      isATiktokChannel: false,
      message: 'Separate caption',
      sender: { id: 1 },
      setReplyToInPayload: payload => payload,
    };

    const payloads = ReplyBox.methods.getMultipleMessagesPayload.call(
      context,
      context.message
    );

    expect(payloads).toHaveLength(2);
    expect(payloads[0]).toMatchObject({
      files: ['signed-audio-blob'],
      message: '',
      contentAttributes: { whatsmeow_recorded_audio: true },
    });
    expect(payloads[1]).toMatchObject({ message: 'Separate caption' });
  });
});
