import { flushPromises, mount } from '@vue/test-utils';
import ResourceVideoPlayer from '../ResourceVideoPlayer.vue';

it('plays, pauses, seeks and changes sound through the custom controls without submitting its parent form', async () => {
  const submit = vi.fn();
  const form = document.createElement('form');
  form.addEventListener('submit', submit);
  document.body.appendChild(form);
  const wrapper = mount(ResourceVideoPlayer, {
    props: { src: '/clip.mp4', name: 'Clip' },
    attachTo: form,
  });
  const video = wrapper.get('video').element;
  expect(video.controls).toBe(false);
  expect(video.muted).toBe(true);
  const play = vi.spyOn(video, 'play').mockImplementation(() => {
    video.dispatchEvent(new Event('play'));
    return Promise.resolve();
  });
  const pause = vi.spyOn(video, 'pause').mockImplementation(() => {
    video.dispatchEvent(new Event('pause'));
  });
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.PLAY_VIDEO"]')
    .trigger('click');
  await flushPromises();
  expect(play).toHaveBeenCalledOnce();
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.PAUSE_VIDEO"]')
    .trigger('click');
  expect(pause).toHaveBeenCalledOnce();
  Object.defineProperty(video, 'duration', { value: 10 });
  await wrapper.get('video').trigger('loadedmetadata');
  await wrapper.get('input[type="range"]').setValue('4');
  expect(video.currentTime).toBe(4);
  expect(wrapper.text()).toContain('00:04 / 00:10');
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.UNMUTE_VIDEO"]')
    .trigger('click');
  expect(video.muted).toBe(false);
  expect(submit).not.toHaveBeenCalled();
  wrapper.unmount();
  form.remove();
});
