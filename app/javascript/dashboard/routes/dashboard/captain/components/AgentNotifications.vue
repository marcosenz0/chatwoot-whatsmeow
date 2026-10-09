<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';
import AiToggleRow from './AiToggleRow.vue';
import NotificationRecipients from './NotificationRecipients.vue';

const props = defineProps({ agentId: { type: Number, default: null } });
const config = defineModel({ type: Object, required: true });
const { t } = useI18n();
const options = ref({ users: [], inboxes: [] });
const testConversation = ref(null);
const testing = ref(false);
onMounted(async () => {
  try {
    const { data } = await MarcosxAiAPI.getNotificationOptions();
    options.value = data;
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  }
});
const addRule = () => {
  config.value.alert_rules.push({
    id: crypto.randomUUID(),
    name: '',
    description: '',
    action: 'notify',
    message: '{contact} · {inbox}\n{reason}\n{url}',
    ...JSON.parse(JSON.stringify(config.value.notifications)),
  });
};
const removeRule = id => {
  config.value.alert_rules = config.value.alert_rules.filter(
    rule => rule.id !== id
  );
};
const testNotification = async () => {
  testing.value = true;
  try {
    await MarcosxAiAPI.testNotification(props.agentId, testConversation.value);
    useAlert(t('MARCOX_AI.AUTOMATION.TEST_QUEUED'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  } finally {
    testing.value = false;
  }
};
</script>

<template>
  <div class="space-y-5">
    <p class="text-sm text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.DESTINATIONS_HINT') }}
    </p>
    <NotificationRecipients
      v-model="config.notifications"
      :users="options.users"
      :inboxes="options.inboxes"
    />
    <AiToggleRow
      v-model="config.pause_on_handoff"
      :label="t('MARCOX_AI.AUTOMATION.PAUSE_HANDOFF')"
      :description="t('MARCOX_AI.AUTOMATION.PAUSE_HANDOFF_HINT')"
    />
    <AiToggleRow
      v-model="config.pause_acknowledgement"
      :label="t('MARCOX_AI.AUTOMATION.ACK')"
      :description="t('MARCOX_AI.AUTOMATION.ACK_HINT')"
    />
    <label class="block text-sm">
      {{ t('MARCOX_AI.AUTOMATION.RESUME_MODE') }}
      <AiSelect
        v-model="config.resume_mode"
        class="mt-2"
        :options="
          ['manual', 'after_human'].map(value => ({
            value,
            label: t(`MARCOX_AI.AUTOMATION.RESUME_${value.toUpperCase()}`),
          }))
        "
        :label="t('MARCOX_AI.AUTOMATION.RESUME_MODE')"
      />
    </label>
    <label v-if="config.resume_mode === 'after_human'" class="block text-sm">
      {{ t('MARCOX_AI.AUTOMATION.RESUME_MINUTES') }}
      <input
        v-model.number="config.resume_after_minutes"
        type="number"
        min="1"
        max="10080"
        class="reset-base mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-background px-3"
      />
    </label>
    <p class="text-xs text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.RESUME_HINT') }}
    </p>
    <div
      v-for="rule in config.alert_rules"
      :key="rule.id"
      class="space-y-3 rounded-xl border border-n-weak p-4"
    >
      <label
        v-for="field in ['name', 'description', 'message']"
        :key="field"
        class="block text-sm"
      >
        {{ t(`MARCOX_AI.AUTOMATION.RULE_${field.toUpperCase()}`) }}
        <textarea
          v-model="rule[field]"
          rows="2"
          class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3"
        />
      </label>
      <p class="text-xs text-n-slate-11">
        {{ t('MARCOX_AI.AUTOMATION.TEMPLATE_HINT') }}
      </p>
      <AiSelect
        v-model="rule.action"
        :options="
          ['notify', 'pause'].map(value => ({
            value,
            label: t(`MARCOX_AI.AUTOMATION.ACTION_${value.toUpperCase()}`),
          }))
        "
        :label="t('MARCOX_AI.AUTOMATION.ACTION')"
      />
      <NotificationRecipients
        v-model="config.alert_rules[config.alert_rules.indexOf(rule)]"
        :users="options.users"
        :inboxes="options.inboxes"
      />
      <Button
        size="sm"
        variant="link"
        color="ruby"
        :label="t('MARCOX_AI.AUTOMATION.REMOVE_RULE')"
        @click="removeRule(rule.id)"
      />
    </div>
    <Button
      size="sm"
      variant="outline"
      icon="i-lucide-plus"
      :label="t('MARCOX_AI.AUTOMATION.ADD_RULE')"
      @click="addRule"
    />
    <div v-if="agentId" class="space-y-3 border-t border-n-weak pt-4">
      <p class="text-xs text-n-slate-11">
        {{ t('MARCOX_AI.AUTOMATION.TEST_HINT') }}
      </p>
      <input
        v-model.number="testConversation"
        type="number"
        min="1"
        class="reset-base h-10 w-full rounded-lg border border-n-weak bg-n-background px-3"
        :placeholder="t('MARCOX_AI.AUTOMATION.TEST_CONVERSATION')"
      />
      <Button
        size="sm"
        :disabled="!testConversation || testing"
        :is-loading="testing"
        :label="t('MARCOX_AI.AUTOMATION.TEST_NOTIFICATION')"
        @click="testNotification"
      />
    </div>
  </div>
</template>
