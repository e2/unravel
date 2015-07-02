#!/usr/bin/env ruby

require 'logger'
require 'open3'
require 'set'
require 'pathname'

# TODO: don't allow replacing the error

module Unravel
  def self.logger
    @@logger ||= Logger.new(STDOUT).tap do |logger|
      logger.level = Logger::DEBUG
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{severity}: #{msg}\n"
      end
    end
  end

  class HumanInterventionNeeded < RuntimeError; end
  class NoKnownRootCause < HumanInterventionNeeded ; end
  class SameCauseReoccurringCause < HumanInterventionNeeded; end

  class NoErrorHandler
    attr_reader :name
    attr_reader :exception
    def initialize(name, ex)
      @name = name
      @exception = ex
    end

    def message
      "Achievement #{name.inspect} is not declared to handle exceptions of type: #{ex.class}"
    end
  end

  class Registry
    attr_reader :achievements, :symptoms, :fixes, :contexts, :errors

    def initialize
      @fixes = {}
      @symptoms = {}
      @achievements = {}
      @contexts = {}
      @errors = {}
    end

    def has_fix_for?(cause)
      @fixes.key?(cause)
    end

    def get_fix_for(cause)
      achievement_or_block = @fixes[cause]
      fail HumanInterventionNeeded, "No fix for: #{cause}" unless achievement_or_block
      achievement_or_block
    end

    def add_fix(name, block)
      fail HumanInterventionNeeded, "fix for root cause #{name} already exists" if @fixes.key?(name)
      @fixes[name] = block
    end

    def get_root_cause(symptom)
      @symptoms[symptom]
    end

    def add_symptom(symptom, root_cause)
      @symptoms[symptom] = root_cause
    end

    def add_achievement(name, &block)
      @achievements[name] = block
    end

    def get_achievement(name)
      @achievements[name].tap do |achievement|
        fail HumanInterventionNeeded, "No such achievement: #{name.inspect}" unless achievement
      end
    end

    def add_error_contexts(name, contexts)
      @contexts[name] ||= contexts
    end

    def error_contexts_for_achievement(name)
      @contexts[name].tap do |context|
        fail HumanInterventionNeeded, "No error handlers for achievement: #{name}" unless context
      end
    end

    def fixable_error(name)
      @errors[name]
    end
  end

  class Session
    class DefaultConfig
      def max_retries
        5
      end
    end

    attr_reader :registry
    attr_reader :config

    class FixableError < RuntimeError
      attr_reader :symptom
      attr_reader :extracted_info
      def initialize(symptom_name, extracted_info)
        @symptom = symptom_name

        # TODO: clean this up
        matchdata = extracted_info
        @extracted_info = matchdata.captures.empty? ? [] : [matchdata]
      end
    end

    def initialize(config)
      @config = config || DefaultConfig.new
      @registry = Registry.new
    end

    def achieve(name, *args)
      check # TODO: overhead?

      prev_causes = Set.new
      max_retries = config.max_retries
      retries_left = max_retries

      begin
        Unravel.logger.info("Achieving (attempt: #{max_retries - retries_left + 1}/#{max_retries}): #{name.inspect}")

        block = registry.get_achievement(name)
        if block.arity >= 0
          unless block.arity == args.size
            fail ArgumentError, "expected #{block.arity} args for #{name.inspect}, got: #{args.inspect}"
          end
        end

        error_contexts = registry.error_contexts_for_achievement(name)

        begin
          res = return_wrap(*args, &block)
        rescue *error_contexts.keys
          ex = $!
          econtext = error_contexts[ex.class]
          unless econtext
            # TODO: not tested
            fail NoErrorHandler.new(name, ex)
          end

          econtext.each do |fix_name|
            error = $!.message
            fix! fix_name, error
          end
          fail
        end

        return true if res == true
        fail NotImplementedError, "#{name} unexpectedly returned #{res.inspect} (expected true or exception)"

      rescue FixableError => error
        Unravel.logger.info("#{name}: Symptom: #{error.symptom.inspect}")

        #Unravel.logger.debug("  -> failed: #{name.inspect}: #{error.symptom.inspect}\n")
        cause = get_root_cause_for(error.symptom)

        fail NoKnownRootCause, "Can't find root cause for: #{error.symptom}, #{error.message}" unless cause

        Unravel.logger.info("#{name}: Cause: #{cause.inspect}")
        if prev_causes.include? cause
          fail SameCauseReoccurringCause, "#{cause.to_s} wasn't ultimately fixed (it occured again)"
        end

        prev_causes << cause
        fix = registry.get_fix_for(cause)
        fix.call(error)

        retries_left -= 1
        retry if retries_left > 0
        fail
      end
    end

    def achievement(name, error_contexts, &block)
      registry.add_achievement(name, &block)
      registry.add_error_contexts(name, error_contexts)
    end

    def error
      registry.errors
    end

    def root_cause_for(mapping)
      symptom, root_cause = *mapping.first
      registry.add_symptom(symptom, root_cause)
    end

    #TODO: move logic to registry
    def fix_for(*args, &block)
      name, achievement = *args
      if block_given?
        if args.size > 1
          fail ArgumentError, "#{args[1..-1].inspect} ignored because of block"
        end
        registry.add_fix(name, block)
      else
        if name.is_a?(Hash)
          name, achievement = *name.first
        end
        # TODO: this recursively calls self (just to provied block), though -
        # is the block_given check needed?
        unless block_given?
          fix_for(name)  do |error|
            achieve(achievement, *error.extracted_info)
          end
        end
      end
    end

    # Shorthand for easy-to-fix and name problems
    def quickfix(error_name, regexp, fix_name, handlers={})
      root_cause_name = "no_#{fix_name}".to_sym
      error[error_name] = regexp
      root_cause_for error_name => root_cause_name
      unless registry.has_fix_for?(root_cause_name)
        fix_for root_cause_name => fix_name
      end
      achievement fix_name, handlers, &method(fix_name)
    end

    private

    def return_wrap(*args, &block)
      Thread.new { return block.yield(*args) }.join
    rescue LocalJumpError => ex
      ex.exit_value
    end

    def check
      logger = Unravel.logger

      res = registry.fixes.keys - registry.symptoms.values
      logger.warn "Unused: #{res.inspect}" unless res.empty?

      res = registry.symptoms.values - registry.fixes.keys
      logger.warn "Unhandled: #{res.inspect}" unless res.empty?

      errors = registry.contexts.values.map(&:values).flatten(2)
      res = errors - registry.symptoms.keys
      logger.warn "Unknown contexts: #{res.inspect}" unless res.empty?

      res = registry.symptoms.keys - errors
      logger.warn "Unused errors: #{res.inspect}" unless res.empty?
    end

    def fix!(name, error)
      regexp = registry.fixable_error(name)
      unless regexp
        fail HumanInterventionNeeded, "Unregistered error: #{name} to match #{error.inspect}"
      end

      # TODO: encoding not tested
      match = regexp.match(error.force_encoding(Encoding::ASCII_8BIT))
      fail FixableError.new(name, match) if match
    end

    def get_root_cause_for(symptom)
      registry.get_root_cause(symptom)
    end
  end
end
