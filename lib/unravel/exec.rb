module Unravel
  class Exec
    class Error < Unravel::HumanInterventionNeeded; end
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
      error = out if error.strip.empty?
      raise Exec::Error, error
    rescue Errno::ENOENT => e
      raise Exec::Error, e.message
    end

    def Capture(args)
      Unravel.logger.debug "  -> Running: #{args.inspect}"
      out, error, status = Open3.capture3(*args)
      return out if status.success?
      Unravel.logger.debug "Errors from #{args.inspect}: -----"
      Unravel.logger.debug "#{error}"
      error = out if error.strip.empty?
      raise Exec::Error, error
    rescue Errno::ENOENT => e
      raise Exec::Error, e.message
    end
  end
end
