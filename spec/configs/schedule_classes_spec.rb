# frozen_string_literal: true

# Companion to schedule_spec.rb: every cron entry must point at a class that
# actually resolves and is performable — a typo'd class name fails silently in
# sidekiq-cron (job loads, never runs).
require 'rails_helper'

RSpec.context 'with resolvable schedule.yml classes' do
  schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

  schedule.each do |name, entry|
    it "#{name} resolves #{entry['class']} and can perform" do
      expect(name).not_to end_with('.rb'), 'cron NAME should not look like a filename'

      klass = entry['class'].constantize
      performable = klass.respond_to?(:perform_later) || # ActiveJob
                    klass.respond_to?(:perform_async) || # Sidekiq::Worker
                    klass.instance_methods.include?(:perform)
      expect(performable).to be(true), "#{entry['class']} has no perform entry point"
    end
  end
end
