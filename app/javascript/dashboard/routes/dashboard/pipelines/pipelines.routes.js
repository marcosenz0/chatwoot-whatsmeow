import { frontendURL } from '../../../helper/URLHelper';

const PipelinesPage = () => import('./PipelinesPage.vue');

const CONVERSATION_PERMISSIONS = [
  'administrator',
  'agent',
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/pipelines'),
    name: 'pipelines_index',
    meta: {
      permissions: CONVERSATION_PERMISSIONS,
    },
    component: PipelinesPage,
  },
];

export default { routes };
