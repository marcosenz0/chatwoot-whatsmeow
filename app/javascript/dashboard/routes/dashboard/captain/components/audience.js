export const defaultAudience = (globalScope, conversationId) => ({
  audience: globalScope ? 'global' : 'conversation',
  conversation_id: globalScope ? null : conversationId,
  contact_ids: [],
  audience_contacts: [],
});

export const audiencePayload = item => ({
  audience: item.audience || 'global',
  conversation_id:
    item.audience === 'conversation' ? item.conversation_id : null,
  contact_ids: item.audience === 'contacts' ? item.contact_ids : [],
});

export const audienceValid = item =>
  item.audience !== 'contacts' || item.contact_ids?.length > 0;
