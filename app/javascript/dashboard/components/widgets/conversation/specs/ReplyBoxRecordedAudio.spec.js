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

describe('Audio recording presence', () => {
  it('renews during actual recording at most every eight seconds', () => {
    vi.useFakeTimers();
    vi.setSystemTime(10000);
    const context = {
      isAWhatsmeowChannel: true,
      lastRecordingPresenceAt: 0,
      toggleTyping: vi.fn(),
    };
    ReplyBox.methods.onRecordProgressChanged.call(context, '00:01');
    ReplyBox.methods.onRecordProgressChanged.call(context, '00:02');
    expect(context.toggleTyping).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(8000);
    ReplyBox.methods.onRecordProgressChanged.call(context, '00:09');
    expect(context.toggleTyping).toHaveBeenCalledTimes(2);
    expect(context.toggleTyping).toHaveBeenLastCalledWith('on', 'audio');
    vi.useRealTimers();
  });

  it('does not advertise recording before the microphone starts', () => {
    const context = {
      isAWhatsmeowChannel: true,
      isRecordingAudio: false,
      toggleTyping: vi.fn(),
      resetAudioRecorderInput: vi.fn(),
    };
    ReplyBox.methods.toggleAudioRecorder.call(context);
    expect(context.toggleTyping).not.toHaveBeenCalled();
    ReplyBox.methods.toggleAudioRecorder.call(context);
    expect(context.toggleTyping).toHaveBeenCalledWith('off', 'audio');
  });
});
