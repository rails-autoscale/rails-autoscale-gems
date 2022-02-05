# frozen_string_literal: true

require "test_helper"
require "judoscale/worker_adapters/que"
require "judoscale/store"
require "que"

module Judoscale
  describe WorkerAdapters::Que do
    def enqueue(queue, run_at)
      ActiveRecord::Base.connection.insert <<~SQL
        INSERT INTO que_jobs (queue, run_at)
        VALUES ('#{queue}', '#{run_at.iso8601(6)}')
      SQL
    end

    subject { WorkerAdapters::Que.instance }

    describe "#enabled?" do
      specify { _(subject).must_be :enabled? }
    end

    describe "#collect!" do
      let(:store) { Store.instance }

      before {
        subject.queues = nil
        ActiveRecord::Base.connection.execute("DELETE FROM que_jobs")
      }
      after { store.clear }

      it "collects latency for each queue" do
        enqueue("default", Time.now - 11)
        enqueue("high", Time.now - 22.2222)

        subject.collect! store

        _(store.measurements.size).must_equal 2
        _(store.measurements[0].queue_name).must_equal "default"
        _(store.measurements[0].value).must_be_within_delta 11000, 5
        _(store.measurements[1].queue_name).must_equal "high"
        _(store.measurements[1].value).must_be_within_delta 22222, 5
      end

      it "logs debug information for each queue being collected" do
        use_config debug: true do
          enqueue("default", Time.now)

          subject.collect! store

          _(log_string).must_match %r{que-qt.default=\d+ms}
        end
      end

      it "skips metrics collection if exceeding max queues configured limit" do
        use_adapter_config :que, max_queues: 2 do
          %w[low default high].each { |queue| enqueue(queue, Time.now) }

          subject.collect! store

          _(store.measurements.size).must_equal 0
          _(log_string).must_match %r{Skipping Que metrics - 3 queues exceeds the 2 queue limit}
        end
      end
    end
  end
end
