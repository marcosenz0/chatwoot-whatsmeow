import { frontendURL } from '../../../helper/URLHelper';

import MarcosxAiPage from './pages/MarcosxAiPage.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/captain'),
    component: MarcosxAiPage,
    name: 'captain_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:navigationPath'),
    component: MarcosxAiPage,
    name: 'captain_assistants_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:pathMatch(.*)*'),
    redirect: to => ({
      name: 'captain_assistants_index',
      params: {
        accountId: to.params.accountId,
        navigationPath: 'overview',
      },
    }),
  },
];
