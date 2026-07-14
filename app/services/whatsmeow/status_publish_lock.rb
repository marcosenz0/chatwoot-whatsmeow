require 'securerandom'

class Whatsmeow::StatusPublishLock
  ACCOUNT_INTERVAL = 15.seconds
  SESSION_INTERVAL = 60.seconds
  OPERATION_TTL = (Whatsmeow::SessionClient.status_timeout + 60).seconds

  pattr_initialize [:status!]

  def acquire
    wait_seconds = cooldown_wait
    return wait_seconds if wait_seconds.positive?
    return mutex_wait(account_mutex_key) unless acquire_key(account_mutex_key)

    wait_seconds = cooldown_wait
    return release_account_and_wait(wait_seconds) if wait_seconds.positive?
    return release_account_and_wait(mutex_wait(session_mutex_key)) unless acquire_key(session_mutex_key)

    wait_seconds = cooldown_wait
    if wait_seconds.positive?
      release
      return wait_seconds
    end

    0
  rescue StandardError
    release
    raise
  end

  def finish
    return unless acquired?

    begin
      ::Redis::Alfred.set(account_cooldown_key, token, ex: ACCOUNT_INTERVAL.to_i)
      ::Redis::Alfred.set(session_cooldown_key, token, ex: SESSION_INTERVAL.to_i)
    ensure
      release
    end
  end

  def release
    Array(@acquired_keys).each do |key|
      ::Redis::Alfred.delete_if_equals(key, token)
    rescue StandardError => e
      Rails.logger.error("[Whatsmeow::StatusPublishLock] Failed to release #{key}: #{e.message}")
    end
    @acquired_keys = []
  end

  private

  def token
    @token ||= SecureRandom.uuid
  end

  def acquire_key(key)
    acquired = ::Redis::Alfred.set(key, token, nx: true, ex: OPERATION_TTL.to_i)
    (@acquired_keys ||= []) << key if acquired
    acquired
  end

  def acquired?
    Array(@acquired_keys).include?(account_mutex_key) && Array(@acquired_keys).include?(session_mutex_key)
  end

  def release_account_and_wait(wait_seconds)
    ::Redis::Alfred.delete_if_equals(account_mutex_key, token)
    @acquired_keys = []
    [wait_seconds, 1].max
  end

  def cooldown_wait
    [ttl(account_cooldown_key), ttl(session_cooldown_key)].max
  end

  def mutex_wait(key)
    ttl(key).clamp(1, 5)
  end

  def ttl(key)
    value = ::Redis::Alfred.ttl(key).to_i
    value.positive? ? value : 0
  end

  def account_mutex_key
    "whatsmeow:status-publish:account:#{status.account_id}:mutex"
  end

  def account_cooldown_key
    "whatsmeow:status-publish:account:#{status.account_id}:cooldown"
  end

  def session_mutex_key
    "whatsmeow:status-publish:#{status.session_key}:mutex"
  end

  def session_cooldown_key
    "whatsmeow:status-publish:#{status.session_key}:cooldown"
  end
end
