import { useI18n } from 'vue-i18n';

export const useStatusTime = () => {
  const { locale, t } = useI18n();

  const formatStatusTime = timestamp => {
    const date = new Date(Number(timestamp) * 1000);
    if (Number.isNaN(date.getTime())) return '';

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const time = new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
      hour: '2-digit',
      minute: '2-digit',
    }).format(date);

    return date >= today
      ? t('WHATSAPP_STATUS.TIME_TODAY', { time })
      : t('WHATSAPP_STATUS.TIME_YESTERDAY', { time });
  };

  return { formatStatusTime };
};
