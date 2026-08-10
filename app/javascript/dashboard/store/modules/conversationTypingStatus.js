import * as types from '../mutation-types';
import ConversationAPI from '../../api/inbox/conversation';
const state = {
  records: {},
};

export const getters = {
  getUserList: $state => id => {
    return $state.records[Number(id)] || [];
  },
};

export const actions = {
  toggleTyping: async (
    _,
    { status, conversationId, isPrivate, typingMedia = 'text' }
  ) => {
    try {
      await ConversationAPI.toggleTyping({
        status,
        conversationId,
        isPrivate,
        typingMedia,
      });
    } catch (error) {
      // Handle error
    }
  },
  create: ({ commit }, { conversationId, user }) => {
    commit(types.default.ADD_USER_TYPING_TO_CONVERSATION, {
      conversationId,
      user,
    });
  },
  destroy: ({ commit }, { conversationId, user }) => {
    commit(types.default.REMOVE_USER_TYPING_FROM_CONVERSATION, {
      conversationId,
      user,
    });
  },
};

export const mutations = {
  [types.default.ADD_USER_TYPING_TO_CONVERSATION]: (
    $state,
    { conversationId, user }
  ) => {
    const records = $state.records[conversationId] || [];
    const existingUserIndex = records.findIndex(
      record => record.id === user.id && record.type === user.type
    );
    const updatedRecords = [...records];
    if (existingUserIndex === -1) updatedRecords.push(user);
    else updatedRecords[existingUserIndex] = user;

    $state.records = {
      ...$state.records,
      [conversationId]: updatedRecords,
    };
  },
  [types.default.REMOVE_USER_TYPING_FROM_CONVERSATION]: (
    $state,
    { conversationId, user }
  ) => {
    const records = $state.records[conversationId] || [];
    const updatedRecords = records.filter(
      record => record.id !== user.id || record.type !== user.type
    );
    $state.records = {
      ...$state.records,
      [conversationId]: updatedRecords,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
