import { frontendURL } from '../../../../helper/URLHelper';
import WhatsAppCloudStudio from './index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/whatsapp-cloud'),
      name: 'whatsapp_cloud_studio',
      component: WhatsAppCloudStudio,
      meta: {
        permissions: ['administrator'],
      },
    },
  ],
};
