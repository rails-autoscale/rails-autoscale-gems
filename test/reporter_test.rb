# frozen_string_literal: true

require "test_helper"
require "judoscale/reporter"
require "judoscale/config"
require "judoscale/store"

module Judoscale
  describe Reporter do
    before { setup_env({"DYNO" => "web.0", "JUDOSCALE_URL" => "http://example.com/api/test-token"}) }

    describe "#report!" do
      after { Store.instance.clear }

      it "reports stored metrics to the API" do
        store = Store.instance

        expected_query = {dyno: "web.0", pid: Process.pid}
        expected_body = "1000000001,11,,\n1000000002,22,high,\n"
        stub = stub_request(:post, "http://example.com/api/test-token/v2/reports")
          .with(query: expected_query, body: expected_body)

        store.push 11, Time.at(1_000_000_001) # web measurement
        store.push 22, Time.at(1_000_000_002), "high" # worker measurement

        Reporter.instance.send :report!, Config.instance, store

        assert_requested stub
      end

      it "logs reporter failures" do
        store = Store.instance
        stub_request(:post, %r{http://example.com/api/test-token/v2/reports})
          .to_return(body: "oops", status: 503)

        store.push 1, Time.at(1_000_000_001) # need some measurement to trigger reporting

        log_io = StringIO.new
        stub_logger = ::Logger.new(log_io)

        Reporter.instance.stub(:logger, stub_logger) {
          Reporter.instance.send :report!, Config.instance, store
        }

        _(log_io.string).must_include "ERROR -- : Reporter failed: 503 - "
      end
    end

    describe "#register!" do
      it "registers the reporter with contextual info" do
        expected_body = {
          registration: {
            pid: Process.pid,
            ruby_version: RUBY_VERSION,
            rails_version: "5.0.fake",
            gem_version: Judoscale::VERSION,
            worker_adapters: ""
          }
        }
        response = {}.to_json
        stub = stub_request(:post, "http://example.com/api/test-token/registrations")
          .with(body: expected_body)
          .to_return(body: response)

        Reporter.instance.send :register!, Config.instance, []

        assert_requested stub
      end
    end
  end
end
