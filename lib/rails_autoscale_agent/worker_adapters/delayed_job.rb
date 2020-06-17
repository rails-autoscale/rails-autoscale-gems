# frozen_string_literal: true

require 'rails_autoscale_agent/logger'

module RailsAutoscaleAgent
  module WorkerAdapters
    class DelayedJob
      include RailsAutoscaleAgent::Logger
      include Singleton

      UNNAMED_QUEUE = '[unnamed queue]'

      class << self
        attr_accessor :queues
      end

      def initialize
        # Track the known queues so we can continue reporting on queues that don't
        # currently have enqueued jobs.
        self.class.queues = Set.new

        install if enabled?
      end

      def enabled?
        defined? ::Delayed
      end

      def collect!(store)
        log_msg = String.new
        t = Time.now.utc
        db_time = t.strftime('%Y-%m-%d %H:%M:%S')

        # Ignore failed jobs (they skew latency measurement due to the original run_at)
        sql = "SELECT queue, min(run_at) FROM delayed_jobs WHERE run_at < '#{db_time}' AND locked_at IS NULL AND failed_at IS NULL GROUP BY queue"
        run_at_by_queue = Hash[ActiveRecord::Base.connection.select_rows(sql)]
        queues = self.class.queues | run_at_by_queue.keys

        queues.each do |queue|
          run_at = run_at_by_queue[queue]
          run_at = Time.parse(run_at) if run_at.is_a?(String)
          latency_ms = run_at ? ((t - run_at)*1000).ceil : 0

          queue = UNNAMED_QUEUE if queue.nil? || queue.empty?
          store.push latency_ms, t, queue
          log_msg << "dj.#{queue}=#{latency_ms} "
        end

        logger.debug log_msg unless log_msg.empty?
      end

      private

      def install
        plugin = Class.new(Delayed::Plugin) do
          require 'delayed_job'

          callbacks do |lifecycle|
            lifecycle.before(:enqueue) do |job, &block|
              queue = job.queue || 'default'
              WorkerAdapters::DelayedJob.queues.add queue
            end
          end
        end

        Delayed::Worker.plugins << plugin
      end
    end
  end
end
