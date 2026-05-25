# frozen_string_literal: true

# One-shot data fix: payment_handles has handle/display_name reversed.
# Run via:  bundle exec rails runner db/scripts/fix_payment_handle_columns.rb
# Idempotent — skips rows that already look correct.

def looks_like_cashtag?(value)
  s = value.to_s.strip
  return false if s.blank?
  return true if s.start_with?('$', '@')
  return false if s.include?(' ')

  s.match?(/\A[a-z0-9_.\-]+\z/i)
end

def looks_like_human_name?(value)
  s = value.to_s.strip
  return false if s.blank?
  return false if s.start_with?('$', '@')

  s.include?(' ') && s.match?(/\A[a-z\s.\-']+\z/i)
end

swapped = 0
skipped = 0

PaymentHandle.find_each do |ph|
  raw_handle  = ph.handle.to_s
  raw_display = ph.try(:display_name).to_s

  if looks_like_human_name?(raw_handle) && looks_like_cashtag?(raw_display)
    puts "SWAPPING id=#{ph.id} platform=#{ph.platform}"
    puts "  before: handle=#{raw_handle.inspect} display_name=#{raw_display.inspect}"
    ph.update_columns(handle: raw_display, display_name: raw_handle)
    ph.reload
    ph.save!
    ph.reload
    puts "  after:  handle=#{ph.handle.inspect} display_name=#{ph.display_name.inspect} normalized=#{ph.normalized_handle.inspect}"
    swapped += 1
  else
    puts "SKIP id=#{ph.id} platform=#{ph.platform} (already correct or ambiguous) handle=#{raw_handle.inspect} display_name=#{raw_display.inspect}"
    skipped += 1
  end
end

puts ''
puts "Done. swapped=#{swapped} skipped=#{skipped}"
