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
const emit = defineEmits(['show-alerts']);
const config = defineModel({ type: Object, required: true });
const { t } = useI18n();
const options = ref({ users: [], inboxes: [] });
const testConversation = ref(null);
const testing = ref(false);
const openRule = ref(null);
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
  openRule.value = config.value.alert_rules.at(-1).id;
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
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('MARCOX_AI.WORKSPACE.DEFAULT_RECIPIENTS') }}
      </h4>
      <Button
        v-if="agentId"
        type="button"
        variant="outline"
        icon="i-lucide-bell-ring"
        :label="t('MARCOX_AI.WORKSPACE.SHOW_PENDING')"
        @click="emit('show-alerts')"
      />
    </div>
    <p class="text-sm text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.DESTINATIONS_HINT') }}
    </p>
    <NotificationRecipients
      v-model="config.notifications"
      :users="options.users"
      :inboxes="options.inboxes"
    />
    <div class="space-y-3 rounded-xl border border-n-weak p-5">
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('MARCOX_AI.WORKSPACE.HUMAN_SUPPORT') }}
      </h4>
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
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('MARCOX_AI.WORKSPACE.RULES') }}
      </h4>
      <Button
        type="button"
        size="sm"
        variant="outline"
        icon="i-lucide-plus"
        :label="t('MARCOX_AI.AUTOMATION.ADD_RULE')"
        @click="addRule"
      />
    </div>
    <p v-if="!config.alert_rules.length" class="text-sm text-n-slate-11">
      {{ t('MARCOX_AI.WORKSPACE.NO_RULES') }}
    </p>
    <details
      v-for="rule in config.alert_rules"
      :key="rule.id"
      :open="openRule === rule.id"
      class="rounded-xl border border-n-weak"
    >
      <summary
        class="flex cursor-pointer list-none items-center justify-between gap-3 p-5"
        @click.prevent="openRule = openRule === rule.id ? null : rule.id"
      >
        <span class="min-w-0"
          ><span class="block truncate text-sm font-semibold text-n-slate-12">{{
            rule.name || t('MARCOX_AI.WORKSPACE.NEW_RULE')
          }}</span>
          <span class="mt-1 block truncate text-xs text-n-slate-11">{{
            rule.description || t('MARCOX_AI.WORKSPACE.RULE_HINT')
          }}</span></span
        >
        <span
          class="shrink-0 rounded-lg bg-n-alpha-2 px-3 py-1 text-xs text-n-slate-11"
          >{{
            t(`MARCOX_AI.AUTOMATION.ACTION_${rule.action.toUpperCase()}`)
          }}</span
        >
        <span
          :class="
            openRule === rule.id
              ? 'i-lucide-chevron-up'
              : 'i-lucide-chevron-down'
          "
          class="size-4 shrink-0 text-n-slate-11"
        />
      </summary>
      <div class="space-y-4 border-t border-n-weak p-5">
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
          type="button"
          size="sm"
          variant="link"
          color="ruby"
          :label="t('MARCOX_AI.AUTOMATION.REMOVE_RULE')"
          @click="removeRule(rule.id)"
        />
      </div>
    </details>
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
        type="button"
        size="sm"
        :disabled="!testConversation || testing"
        :is-loading="testing"
        :label="t('MARCOX_AI.AUTOMATION.TEST_NOTIFICATION')"
        @click="testNotification"
      />
    </div>
  </div>
</template>
