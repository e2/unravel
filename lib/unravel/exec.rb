module Unravel
  class Exec
    class Error < Unravel::HumanInterventionNeeded
      class Standard < Error
      end

      class Silent < Error
        attr_reader :exitcode
        attr_reader :exitstatus
        def initialize(exitcode, stdout)
          @exitcode = exitcode
          @stdout = stdout
          super()
        end

        def to_s
          message
        end

        def message
          lines = @stdout.lines.to_a
          output =
            if lines.size > 1
              indent = "\n  stdout"
              "#{indent}: #{lines * indent}\n"
            else
              "stdout: #{@stdout.inspect}"
            end
          "No stderr available: #{output} (exited with #{@exitcode})"
        end
      end
    end
  end

  class << self
    def run(*args)
      Exec(args)
    end

    def Exec(args)
      Unravel.logger.debug "  -> Running: #{args.inspect}"
      out, error, status = Open3.capture3(*args)
      Unravel.logger.debug "Output from #{args.inspect}: -----"
      Unravel.logger.debug "#{out}"
      return true if status.success?
      Unravel.logger.debug "Errors from #{args.inspect}: -----"
      Unravel.logger.debug "#{error}"

      # TODO: is strip a good idea?
      raise Exec::Error::Silent.new(status.exitstatus, out) if error.strip.empty?
      raise Exec::Error::Standard, error
    rescue Errno::ENOENT => e
      raise Exec::Error::ENOENT, e.message
    end

    def Capture(args)
      Unravel.logger.debug "  -> Running: #{args.inspect}"
      out, error, status = Open3.capture3(*args)
      return out if status.success?
      Unravel.logger.debug "Errors from #{args.inspect}: -----"
      Unravel.logger.debug "#{error}"
      error = out if error.strip.empty?
      raise Exec::Error::Standard, error
    rescue Errno::ENOENT => e
      raise Exec::Error::ENOENT, e.message
    end
  end
end
