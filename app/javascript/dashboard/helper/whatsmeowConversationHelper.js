import { frontendURL, conversationUrl } from './URLHelper';

export const whatsmeowDirectConversationPayload = participant => ({
  participant_jid: participant.jid || participant.participantJid || '',
  participant_phone:
    participant.phoneNumber || participant.participantPhone || '',
  participant_name: participant.name || participant.participantName || '',
  profile_picture_url:
    participant.profilePictureUrl || participant.profile_picture_url || '',
});

export const whatsmeowConversationPath = ({ route, inboxId, conversationId }) =>
  frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      activeInbox: route.params.inbox_id || inboxId,
      id: conversationId,
      label: route.params.label,
      teamId: route.params.teamId,
      foldersId: route.name?.includes('custom_view') ? route.params.id : 0,
    })
  );
