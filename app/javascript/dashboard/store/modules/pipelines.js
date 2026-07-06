import PipelinesAPI from '../../api/pipelines';

const SET_PIPELINES = 'SET_PIPELINES';
const SET_BOARD = 'SET_BOARD';
const SET_UI_FLAGS = 'SET_UI_FLAGS';
const ADD_PIPELINE = 'ADD_PIPELINE';
const UPDATE_PIPELINE = 'UPDATE_PIPELINE';
const DELETE_PIPELINE = 'DELETE_PIPELINE';

export const state = {
  records: [],
  board: null,
  uiFlags: {
    isFetching: false,
    isFetchingBoard: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isMovingConversation: false,
  },
};

export const getters = {
  getPipelines(_state) {
    return _state.records;
  },
  getBoard(_state) {
    return _state.board;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getPipelineById: _state => id => {
    return _state.records.find(record => record.id === Number(id)) || {};
  },
  getPipelineStageOptions(_state) {
    return _state.records.flatMap(pipeline =>
      (pipeline.stages || []).map(stage => ({
        id: stage.id,
        name: `${pipeline.name} / ${stage.name}`,
        pipeline_id: pipeline.id,
      }))
    );
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(SET_UI_FLAGS, { isFetching: true });
    try {
      const response = await PipelinesAPI.get();
      commit(SET_PIPELINES, response.data.payload);
      return response.data.payload;
    } finally {
      commit(SET_UI_FLAGS, { isFetching: false });
    }
  },

  getBoard: async ({ commit }, { id, params = {} }) => {
    commit(SET_UI_FLAGS, { isFetchingBoard: true });
    try {
      const response = await PipelinesAPI.board(id, params);
      commit(SET_BOARD, response.data.payload);
      return response.data.payload;
    } finally {
      commit(SET_UI_FLAGS, { isFetchingBoard: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit(SET_UI_FLAGS, { isCreating: true });
    try {
      const response = await PipelinesAPI.create(payload);
      commit(ADD_PIPELINE, response.data);
      return response.data;
    } finally {
      commit(SET_UI_FLAGS, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit(SET_UI_FLAGS, { isUpdating: true });
    try {
      const response = await PipelinesAPI.update(id, payload);
      commit(UPDATE_PIPELINE, response.data);
      return response.data;
    } finally {
      commit(SET_UI_FLAGS, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(SET_UI_FLAGS, { isDeleting: true });
    try {
      await PipelinesAPI.delete(id);
      commit(DELETE_PIPELINE, id);
    } finally {
      commit(SET_UI_FLAGS, { isDeleting: false });
    }
  },

  createStage: async ({ dispatch }, { pipelineId, stage }) => {
    await PipelinesAPI.createStage(pipelineId, { stage });
    return dispatch('get');
  },

  updateStage: async ({ dispatch }, { pipelineId, stageId, stage }) => {
    await PipelinesAPI.updateStage(pipelineId, stageId, { stage });
    return dispatch('get');
  },

  deleteStage: async ({ dispatch }, { pipelineId, stageId }) => {
    await PipelinesAPI.deleteStage(pipelineId, stageId);
    return dispatch('get');
  },

  moveConversation: async ({ commit }, payload) => {
    commit(SET_UI_FLAGS, { isMovingConversation: true });
    try {
      const response = await PipelinesAPI.moveConversation(payload);
      commit('UPDATE_CONVERSATION', response.data, { root: true });
      return response.data;
    } finally {
      commit(SET_UI_FLAGS, { isMovingConversation: false });
    }
  },
};

export const mutations = {
  [SET_PIPELINES](_state, records) {
    _state.records = records || [];
  },
  [SET_BOARD](_state, board) {
    _state.board = board;
  },
  [SET_UI_FLAGS](_state, flags) {
    _state.uiFlags = { ..._state.uiFlags, ...flags };
  },
  [ADD_PIPELINE](_state, pipeline) {
    _state.records = [..._state.records, pipeline];
  },
  [UPDATE_PIPELINE](_state, pipeline) {
    _state.records = _state.records.map(record =>
      record.id === pipeline.id ? pipeline : record
    );
  },
  [DELETE_PIPELINE](_state, id) {
    _state.records = _state.records.filter(record => record.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
