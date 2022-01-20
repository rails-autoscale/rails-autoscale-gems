# frozen_string_literal: true

require "judoscale/config"
require "logger"

module Judoscale
  module Logger
    def logger
      @logger ||= LoggerProxy.new(Config.instance.logger)
    end
  end

  class LoggerProxy < Struct.new(:logger)
    TAG = "[Judoscale]"
    DEBUG_TAG = "[DEBUG]"

    def error(*msgs)
      logger.error tag(msgs)
    end

    def warn(*msgs)
      logger.warn tag(msgs)
    end

    def info(*msgs)
      logger.info tag(msgs) unless Config.instance.quiet?
    end

    def debug(*msgs)
      # Silence debug logs by default to avoiding being overly chatty (Rails logger defaults
      # to DEBUG level in production). Setting JUDOSCALE_DEBUG=true enables debug logs,
      # even if the underlying logger severity level is INFO.
      if Config.instance.debug?
        if logger.respond_to?(:debug?) && logger.debug?
          logger.debug tag(msgs)
        elsif logger.respond_to?(:info?) && logger.info?
          logger.info tag(msgs.map { |msg| "#{DEBUG_TAG} #{msg}" })
        end
      end
    end

    private

    def tag(msgs)
      msgs.map { |msg| "#{TAG} #{msg}" }.join("\n")
    end
  end
end
